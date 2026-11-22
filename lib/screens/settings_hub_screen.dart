import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:local_auth/local_auth.dart';
import '../components/app_logo.dart';
import '../components/app_update_dialog.dart';
import '../core/app_notification.dart';
import '../core/app_settings_service.dart';
import '../core/app_theme.dart';
import '../core/app_update_service.dart';
import '../core/app_version.dart';
import '../core/cloud_service.dart';
import '../core/license_service.dart';
import '../core/security_storage_service.dart';
import 'backup_screen.dart';
import 'subscription_screen.dart';

class SettingsHubScreen extends StatefulWidget {
  final int initialTabIndex;
  const SettingsHubScreen({super.key, this.initialTabIndex = 0});

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'إعدادات النظام'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded), text: 'الإعدادات العامة'),
            Tab(icon: Icon(Icons.backup_rounded), text: 'النسخ الاحتياطي والكاش'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _GeneralSettingsTab(),
          BackupScreen(embedded: true),
        ],
      ),
    );
  }
}

class _GeneralSettingsTab extends StatefulWidget {
  const _GeneralSettingsTab();

  @override
  State<_GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<_GeneralSettingsTab> {
  bool _biometricEnabled = false;
  bool _biometricSupported = true;
  int _biometricTimeoutSecs = 30;
  bool _backupEncryptionEnabled = true;
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isCheckingUpdate = false;
  bool _isSyncingLicense = false;
  LicenseInfo? _licenseInfo;

  @override
  void initState() {
    super.initState();
    LicenseService.statusNotifier.addListener(_onLicenseChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    LicenseService.statusNotifier.removeListener(_onLicenseChanged);
    super.dispose();
  }

  void _onLicenseChanged() {
    if (mounted) {
      setState(() {
        _licenseInfo = LicenseService.statusNotifier.value;
      });
    }
  }

  Future<void> _loadSettings() async {
    final enabled = await AppSettingsService.isBiometricEnabled();
    final supported = await AppSettingsService.isBiometricHardwareSupported();
    final timeout = await AppSettingsService.getBiometricTimeoutSeconds();
    final encrypt = await AppSettingsService.isBackupEncryptionEnabled();
    final license = await LicenseService.checkStatus();

    if (mounted) {
      setState(() {
        _biometricEnabled = enabled;
        _biometricSupported = supported;
        _biometricTimeoutSecs = timeout;
        _backupEncryptionEnabled = encrypt;
        _licenseInfo = license;
        _isLoading = false;
      });
    }

    // فحص وتحديث فوري لحالة الاشتراك من سوبا بيز لحظياً
    if (!kIsWeb) {
      SecurityStorageService.getDeviceCode().then((code) async {
        final sub = await CloudService.checkAndSyncSubscriptionStatus(code);
        if (sub != null && mounted) {
          final updated = await LicenseService.checkStatus();
          if (mounted) {
            setState(() => _licenseInfo = updated);
          }
        }
      });
    }
  }

  Future<void> _manualSyncLicense() async {
    setState(() => _isSyncingLicense = true);
    final code = await SecurityStorageService.getDeviceCode();
    final sub = await CloudService.checkAndSyncSubscriptionStatus(code);
    final license = await LicenseService.checkStatus();
    if (mounted) {
      setState(() {
        _licenseInfo = license;
        _isSyncingLicense = false;
      });
      if (sub != null && sub.isActive) {
        AppNotification.showSuccess(
          context,
          'تم تحديث الاشتراك بنجاح! متبقي ${_licenseInfo?.daysRemaining ?? 0} يوماً.',
        );
      } else {
        AppNotification.showInfo(context, 'تم فحص وتحديث حالة الاشتراك بنجاح.');
      }
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_isUpdating) return;

    if (value && !_biometricSupported) {
      AppNotification.showError(
        context,
        'هذا الجهاز لا يدعم مستشعر البصمة أو قفل الشاشة حالياً.',
      );
      return;
    }

    setState(() => _isUpdating = true);

    try {
      if (value) {
        final auth = LocalAuthentication();
        final didAuth = await auth.authenticate(
          localizedReason: 'قم بمسح بصمة الإصبع لتأكيد تفعيل الحماية',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );

        if (!didAuth) {
          if (mounted) {
            setState(() => _isUpdating = false);
            AppNotification.showError(context, 'لم يتم التحقق من البصمة، لم يُفعّل القفل.');
          }
          return;
        }
      }

      await AppSettingsService.setBiometricEnabled(value);
      await AppSettingsService.markBiometricPrompted();

      if (mounted) {
        setState(() {
          _biometricEnabled = value;
          _isUpdating = false;
        });
        AppNotification.showSuccess(
          context,
          value
              ? 'تم تفعيل الدخول بالبصمة والقفل التلقائي بنجاح'
              : 'تم إلغاء قفل البصمة — سيفتح التطبيق مباشرة',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUpdating = false);
        AppNotification.showError(context, 'تعذر التحقق من البصمة على هذا الجهاز.');
      }
    }
  }

  Future<void> _openEditShowroomProfileDialog() async {
    final current = AppSettingsService.showroomProfileNotifier.value;
    final nameCtrl = TextEditingController(text: current.name);
    final subCtrl = TextEditingController(text: current.subtitle);
    final phoneCtrl = TextEditingController(text: current.phone);
    final addrCtrl = TextEditingController(text: current.address);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: AppTheme.modalSheetPadding(ctx, horizontal: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store_mall_directory_rounded,
                          color: AppTheme.accentOnSurface(ctx), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'تخصيص بيانات وهوية المعرض',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(ctx),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المعرض / الشركة *',
                  hintText: 'مثال: معارض النور للأثاث',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subCtrl,
                decoration: const InputDecoration(
                  labelText: 'الوصف المختصر (يظهر في الهيدر وكشوف الحساب)',
                  prefixIcon: Icon(Icons.subtitles_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم هاتف المعرض (اختياري)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'عنوان المعرض (اختياري)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavy,
                  foregroundColor: AppTheme.royalGold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await AppSettingsService.saveShowroomProfile(
                    current.copyWith(
                      name: nameCtrl.text.trim(),
                      subtitle: subCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      address: addrCtrl.text.trim(),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    AppNotification.showSuccess(
                      context,
                      'تم حفظ بيانات المعرض وتحديث الواجهات وكشوف الحساب فوراً',
                    );
                  }
                },
                icon: const Icon(Icons.save_rounded),
                label: const Text(
                  'حفظ بيانات المعرض',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      nameCtrl.dispose();
      subCtrl.dispose();
      phoneCtrl.dispose();
      addrCtrl.dispose();
    });
  }

  Future<void> _pickCustomLogo() async {
    try {
      final path = await AppSettingsService.pickAndSaveCustomLogo();
      if (!mounted) return;
      if (path != null) {
        AppNotification.showSuccess(context, 'تم تحديث شعار المعرض بنجاح');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(context, 'تعذر تحديث الشعار: $e');
      }
    }
  }

  Future<void> _resetLogo() async {
    await AppSettingsService.resetCustomLogoToDefault();
    if (mounted) {
      AppNotification.showInfo(context, 'تمت استعادة الشعار الافتراضي لـ ${AppVersion.appName}');
    }
  }

  Future<void> _checkForUpdatesManually() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    try {
      final update = await AppUpdateService.checkForUpdate(silent: false);
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (update != null) {
        await AppUpdateDialog.show(context, update);
      } else {
        AppNotification.showSuccess(
          context,
          'تطبيقك محدث بالفعل على أحدث إصدار (${AppVersion.displayVersion}).',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);
      AppNotification.showError(
        context,
        'تعذر التحقق من وجود تحديثات. يرجى التأكد من اتصال الإنترنت.',
      );
    }
  }

  Future<void> _handleBackupEncryptionToggle(bool val) async {
    await AppSettingsService.setBackupEncryptionEnabled(val);
    if (!mounted) return;
    setState(() => _backupEncryptionEnabled = val);
    AppNotification.showInfo(
      context,
      val
          ? 'تم تفعيل تشفير النسخ الاحتياطية المصدرة (AES-256)'
          : 'تم تعطيل التشفير للنسخ المصدرة (ملف SQLite مباشر)',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isDark = AppTheme.isDark(context);

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. إشعار التحديث الجديد إن وُجد
          ValueListenableBuilder<AppUpdateInfo?>(
            valueListenable: AppUpdateService.availableUpdateNotifier,
            builder: (_, update, __) {
              if (update == null) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF162D4A), AppTheme.primaryNavy],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.royalGold, width: 1.5),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.royalGold.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.new_releases_rounded,
                              color: AppTheme.royalGold, size: 24),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تحديث جديد متوفر (${update.latestVersion})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'إصدارك الحالي: ${AppVersion.displayVersion}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.royalGold,
                          foregroundColor: AppTheme.primaryNavy,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => AppUpdateDialog.show(context, update),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: const Text('تحديث التطبيق الآن',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. المظهر والوضع الليلي / النهاري
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.borderColor(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_rounded,
                          color: AppTheme.accentOnSurface(context), size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'المظهر والوضع الليلي',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppSettingsService.themeModeNotifier,
                    builder: (_, mode, __) {
                      final darkActive = mode == ThemeMode.dark;
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor(context)),
                        ),
                        child: SwitchListTile(
                          value: darkActive,
                          onChanged: (val) async {
                            await AppSettingsService.setThemeMode(
                              val ? ThemeMode.dark : ThemeMode.light,
                            );
                          },
                          activeThumbColor: AppTheme.primaryNavy,
                          activeTrackColor: AppTheme.royalGold.withValues(alpha: 0.7),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: darkActive
                                  ? AppTheme.primaryNavy
                                  : Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              darkActive
                                  ? Icons.dark_mode_rounded
                                  : Icons.light_mode_rounded,
                              color: darkActive
                                  ? AppTheme.royalGold
                                  : Colors.amber.shade900,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            darkActive ? 'الوضع الليلي (مفعّل)' : 'الوضع النهاري (مفعّل)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(
                            darkActive
                                ? 'مظهر داكن مريح للعين للعمل المسائي'
                                : 'اضغط للتبديل الفوري إلى الوضع الليلي',
                            style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3. بيانات وهوية المعرض القابلة للتخصيص التجاري (White-Labeling)
          ValueListenableBuilder<ShowroomProfile>(
            valueListenable: AppSettingsService.showroomProfileNotifier,
            builder: (_, profile, __) {
              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppTheme.royalGold.withValues(alpha: 0.45)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storefront_rounded,
                              color: AppTheme.accentOnSurface(context), size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'بيانات وشعار المعرض',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const AppLogo(size: 56),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile.displayName,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.displaySubtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted(context),
                                  ),
                                ),
                                if (profile.phone.isNotEmpty)
                                  Text(
                                    'هاتف: ${profile.phone}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textMuted(context),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryNavy,
                              foregroundColor: AppTheme.royalGold,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _openEditShowroomProfileDialog,
                            icon: const Icon(Icons.edit_rounded, size: 17),
                            label: const Text('تعديل اسم وبيانات المعرض',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                          ),
                          if (!kIsWeb)
                            OutlinedButton.icon(
                              onPressed: _pickCustomLogo,
                              icon: const Icon(Icons.image_outlined, size: 17),
                              label: const Text('تغيير الشعار',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            ),
                          if (!kIsWeb && profile.hasCustomLogo)
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                              onPressed: _resetLogo,
                              icon: const Icon(Icons.restore_rounded, size: 17),
                              label: const Text('الشعار الافتراضي', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // 4. الأمان وحماية التطبيق بالبصمة وتشفير النسخ
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.borderColor(context)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.security_rounded,
                          color: AppTheme.accentOnSurface(context), size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'الأمان وحماية البيانات',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: _biometricEnabled
                          ? Colors.green.withValues(alpha: isDark ? 0.12 : 0.06)
                          : AppTheme.subtleBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _biometricEnabled
                            ? Colors.green.withValues(alpha: 0.4)
                            : AppTheme.borderColor(context),
                      ),
                    ),
                    child: SwitchListTile(
                      value: _biometricEnabled,
                      onChanged: _isUpdating ? null : _toggleBiometric,
                      activeThumbColor: AppTheme.primaryNavy,
                      activeTrackColor: AppTheme.royalGold.withValues(alpha: 0.65),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _biometricEnabled
                              ? AppTheme.primaryNavy
                              : AppTheme.subtleBg(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: _biometricEnabled
                              ? AppTheme.royalGold
                              : AppTheme.textMuted(context),
                          size: 26,
                        ),
                      ),
                      title: const Text(
                        'تفعيل الدخول والقفل التلقائي بالبصمة',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      subtitle: Text(
                        !_biometricSupported
                            ? 'الجهاز الحالي لا يدعم مستشعر البصمة'
                            : (_biometricEnabled
                                ? 'محمية ومعزولة: تطلب البصمة عند الفتح وعند العودة من الخلفية'
                                : 'معطّلة: يفتح البرنامج مباشرة بدون بصمة'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _biometricEnabled
                              ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                              : AppTheme.textMuted(context),
                        ),
                      ),
                    ),
                  ),
                  if (_biometricEnabled) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'مهلة القفل عند العودة من الخلفية:',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textBody(context),
                          ),
                        ),
                        const Spacer(),
                        DropdownButton<int>(
                          value: _biometricTimeoutSecs,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('فوري')),
                            DropdownMenuItem(value: 30, child: Text('30 ثانية')),
                            DropdownMenuItem(value: 120, child: Text('دقيقتان')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await AppSettingsService.setBiometricTimeoutSeconds(v);
                            setState(() => _biometricTimeoutSecs = v);
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor(context)),
                    ),
                    child: SwitchListTile(
                      value: _backupEncryptionEnabled,
                      onChanged: _handleBackupEncryptionToggle,
                      activeThumbColor: AppTheme.primaryNavy,
                      activeTrackColor: AppTheme.royalGold.withValues(alpha: 0.65),
                      secondary: Icon(
                        Icons.enhanced_encryption_rounded,
                        color: _backupEncryptionEnabled
                            ? Colors.teal
                            : AppTheme.textMuted(context),
                      ),
                      title: const Text(
                        'تشفير النسخ الاحتياطية المصدرة (AES-256)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        'يحمي ملفات النسخ عند التصدير أو المشاركة عبر واتساب بصيغة (.mtbk)',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 5. بطاقة الترخيص والتفعيل التجاري
          if (_licenseInfo != null)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: _licenseInfo!.isActivated
                      ? Colors.green.withValues(alpha: 0.5)
                      : AppTheme.royalGold.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _licenseInfo!.isActivated
                              ? Icons.verified_rounded
                              : Icons.workspace_premium_rounded,
                          color: _licenseInfo!.isActivated ? Colors.green : AppTheme.royalGold,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الترخيص والتفعيل التجاري',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تحديث حالة الاشتراك من السحابة',
                          icon: _isSyncingLicense
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync_rounded, size: 20),
                          onPressed: _isSyncingLicense ? null : _manualSyncLicense,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _licenseInfo!.isActivated
                                ? Colors.green.withValues(alpha: 0.16)
                                : Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _licenseInfo!.isActivated
                                ? (_licenseInfo!.isPermanent
                                    ? 'مفعّل دائم'
                                    : 'مفعّل (${_licenseInfo!.daysRemaining} يوم متبقي)')
                                : (_licenseInfo!.state == LicenseState.trial
                                    ? 'تجريبي (${_licenseInfo!.trialDaysRemaining} يوم)'
                                    : 'منتهي'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _licenseInfo!.isActivated
                                  ? Colors.green.shade700
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'معرف الجهاز: ',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
                        ),
                        Expanded(
                          child: SelectableText(
                            _licenseInfo!.deviceCode,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'نسخ معرف الجهاز',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _licenseInfo!.deviceCode));
                            AppNotification.showSuccess(context, 'تم نسخ معرف الجهاز');
                          },
                        ),
                      ],
                    ),
                    if (_licenseInfo!.expiresAt != null && !_licenseInfo!.isPermanent)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(
                          'صالح حتى: ${intl.DateFormat('yyyy-MM-dd').format(_licenseInfo!.expiresAt!)} (متبقي ${_licenseInfo!.daysRemaining} يوماً)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _licenseInfo!.daysRemaining > 5
                                ? Colors.green.shade700
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: AppTheme.royalGold,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubscriptionScreen(
                                deviceCode: _licenseInfo!.deviceCode,
                              ),
                            ),
                          );
                          if (updated == true || mounted) {
                            await _loadSettings();
                          }
                        },
                        icon: const Icon(Icons.star_rounded, size: 20),
                        label: Text(
                          _licenseInfo!.isActivated ? 'تجديد / ترقية الاشتراك' : 'اشترك الآن',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),

          // 6. بطاقة معلومات التطبيق والإصدار والتحديثات
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.royalGold.withValues(alpha: 0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const AppLogo(size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${AppVersion.appName} (${AppVersion.appNameEn})',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'إدارة المخازن، المنجدين، وطلبات العملاء',
                              style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryNavy,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'الإصدار ${AppVersion.fullVersion}',
                                style: const TextStyle(
                                  color: AppTheme.royalGold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<AppUpdateInfo?>(
                    valueListenable: AppUpdateService.availableUpdateNotifier,
                    builder: (_, update, __) {
                      return SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentOnSurface(context),
                            side: BorderSide(
                              color: update != null
                                  ? const Color(0xFFE53935)
                                  : AppTheme.borderColor(context),
                              width: update != null ? 1.5 : 1.0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isCheckingUpdate ? null : _checkForUpdatesManually,
                          icon: _isCheckingUpdate
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Badge(
                                  isLabelVisible: update != null,
                                  label: const Text('1',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  backgroundColor: const Color(0xFFE53935),
                                  child: const Icon(Icons.system_update_rounded, size: 20),
                                ),
                          label: Text(
                            _isCheckingUpdate
                                ? 'جارٍ التحقق من التحديثات...'
                                : (update != null
                                    ? 'يتوفر تحديث جديد (${update.latestVersion})'
                                    : 'التحقق من التحديثات'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: update != null
                                  ? const Color(0xFFE53935)
                                  : AppTheme.accentOnSurface(context),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
