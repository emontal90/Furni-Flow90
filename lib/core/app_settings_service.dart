import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'app_version.dart';
import 'db_helper.dart';
import 'security_storage_service.dart';

/// بيانات هوية المعرض القابلة للتخصيص التجاري لكل عميل
class ShowroomProfile {
  final String name;
  final String subtitle;
  final String phone;
  final String address;
  final String? customLogoPath;

  const ShowroomProfile({
    this.name = AppVersion.appName,
    this.subtitle = 'نظام إدارة المعارض والمخازن والطلبيات',
    this.phone = '',
    this.address = '',
    this.customLogoPath,
  });

  String get displayName => name.trim().isNotEmpty ? name.trim() : AppVersion.appName;
  String get displaySubtitle =>
      subtitle.trim().isNotEmpty ? subtitle.trim() : 'نظام إدارة المعارض والمخازن والطلبيات';

  bool get hasCustomLogo =>
      customLogoPath != null && customLogoPath!.trim().isNotEmpty;

  ShowroomProfile copyWith({
    String? name,
    String? subtitle,
    String? phone,
    String? address,
    String? customLogoPath,
    bool clearLogo = false,
  }) {
    return ShowroomProfile(
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      customLogoPath: clearLogo ? null : (customLogoPath ?? this.customLogoPath),
    );
  }
}

/// خدمة إدارة إعدادات التطبيق العامة وهوية المعرض والوضع الليلي وحماية البصمة
class AppSettingsService {
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricPromptedKey = 'biometric_prompted';
  static const String _biometricTimeoutKey = 'biometric_timeout_seconds';
  static const String _themeModeKey = 'theme_mode';
  static const String _showroomNameKey = 'showroom_name';
  static const String _showroomSubtitleKey = 'showroom_subtitle';
  static const String _showroomPhoneKey = 'showroom_phone';
  static const String _showroomAddressKey = 'showroom_address';
  static const String _showroomLogoPathKey = 'showroom_logo_path';
  static const String _backupEncryptKey = 'backup_encryption_enabled';

  static const MethodChannel _brandingChannel =
      MethodChannel('com.example.furniture_erp/backup_transfer');

  /// إشعارات لحظية لتحديث السمة وهوية المعرض في كامل التطبيق فوراً
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static final ValueNotifier<ShowroomProfile> showroomProfileNotifier =
      ValueNotifier<ShowroomProfile>(const ShowroomProfile());

  static Future<void> initialize() async {
    await loadThemeMode();
    await loadShowroomProfile();
    await _migrateLegacyBiometricSettingIfNeeded();
  }

  static Future<String?> getSetting(String key) async {
    try {
      final db = await DBHelper.instance.database;
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await DBHelper.instance.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // الوضع الليلي والنهاري (Theme Mode)
  // ---------------------------------------------------------------------------
  static Future<ThemeMode> loadThemeMode() async {
    final raw = await SecurityStorageService.getString(_themeModeKey) ??
        await getSetting(_themeModeKey);
    ThemeMode mode = ThemeMode.light;
    if (raw == 'dark') {
      mode = ThemeMode.dark;
    } else if (raw == 'system') {
      mode = ThemeMode.system;
    }
    themeModeNotifier.value = mode;
    return mode;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final val = mode == ThemeMode.dark
        ? 'dark'
        : (mode == ThemeMode.system ? 'system' : 'light');
    themeModeNotifier.value = mode;
    await SecurityStorageService.setString(_themeModeKey, val);
    try {
      await setSetting(_themeModeKey, val);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // هوية المعرض الديناميكية (White-Label Showroom Profile)
  // ---------------------------------------------------------------------------
  static Future<ShowroomProfile> loadShowroomProfile() async {
    final name = await getSetting(_showroomNameKey) ??
        await SecurityStorageService.getString(_showroomNameKey) ??
        AppVersion.appName;
    final subtitle = await getSetting(_showroomSubtitleKey) ??
        await SecurityStorageService.getString(_showroomSubtitleKey) ??
        'نظام إدارة المعارض والمخازن والطلبيات';
    final phone = await getSetting(_showroomPhoneKey) ??
        await SecurityStorageService.getString(_showroomPhoneKey) ??
        '';
    final address = await getSetting(_showroomAddressKey) ??
        await SecurityStorageService.getString(_showroomAddressKey) ??
        '';
    String? logoPath = await getSetting(_showroomLogoPathKey) ??
        await SecurityStorageService.getString(_showroomLogoPathKey);

    if (logoPath != null && logoPath.isNotEmpty && !kIsWeb) {
      if (!await File(logoPath).exists()) {
        logoPath = null;
      }
    }

    final profile = ShowroomProfile(
      name: name,
      subtitle: subtitle,
      phone: phone,
      address: address,
      customLogoPath: (logoPath != null && logoPath.trim().isNotEmpty) ? logoPath : null,
    );
    showroomProfileNotifier.value = profile;
    return profile;
  }

  static Future<void> saveShowroomProfile(ShowroomProfile profile) async {
    final cleanName = profile.name.trim().isEmpty ? AppVersion.appName : profile.name.trim();
    final cleanSub = profile.subtitle.trim().isEmpty
        ? 'نظام إدارة المعارض والمخازن والطلبيات'
        : profile.subtitle.trim();
    final cleanPhone = profile.phone.trim();
    final cleanAddr = profile.address.trim();
    final cleanLogo = profile.customLogoPath?.trim() ?? '';

    await setSetting(_showroomNameKey, cleanName);
    await setSetting(_showroomSubtitleKey, cleanSub);
    await setSetting(_showroomPhoneKey, cleanPhone);
    await setSetting(_showroomAddressKey, cleanAddr);
    await setSetting(_showroomLogoPathKey, cleanLogo);

    await SecurityStorageService.setString(_showroomNameKey, cleanName);
    await SecurityStorageService.setString(_showroomSubtitleKey, cleanSub);
    await SecurityStorageService.setString(_showroomPhoneKey, cleanPhone);
    await SecurityStorageService.setString(_showroomAddressKey, cleanAddr);
    await SecurityStorageService.setString(
      _showroomLogoPathKey,
      cleanLogo.isEmpty ? null : cleanLogo,
    );

    showroomProfileNotifier.value = ShowroomProfile(
      name: cleanName,
      subtitle: cleanSub,
      phone: cleanPhone,
      address: cleanAddr,
      customLogoPath: cleanLogo.isEmpty ? null : cleanLogo,
    );
  }

  /// اختيار صورة شعار مخصصة للمعرض من الهاتف أو ويندوز وحفظها داخل مجلد التطبيق
  static Future<String?> pickAndSaveCustomLogo() async {
    if (kIsWeb) return null;
    String? pickedPath;

    if (Platform.isAndroid) {
      pickedPath = await _brandingChannel.invokeMethod<String>('pickLogoImage');
    } else if (Platform.isWindows) {
      pickedPath = await _pickFileOnWindows(
        title: 'اختر شعار المعرض (PNG / JPG)',
        filter: 'Image Files (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp',
      );
    }

    if (pickedPath == null || pickedPath.trim().isEmpty) return null;
    final src = File(pickedPath);
    if (!await src.exists()) return null;

    final supportDir = await getApplicationSupportDirectory();
    final brandDir = Directory(p.join(supportDir.path, 'branding'));
    if (!await brandDir.exists()) {
      await brandDir.create(recursive: true);
    }

    final ext = p.extension(pickedPath).toLowerCase();
    final safeExt = (ext == '.jpg' || ext == '.jpeg' || ext == '.webp') ? ext : '.png';
    final destFile = File(
      p.join(brandDir.path, 'showroom_logo_${DateTime.now().millisecondsSinceEpoch}$safeExt'),
    );
    await src.copy(destFile.path);

    // حذف الشعارات القديمة لتوفير المساحة
    try {
      for (final entity in brandDir.listSync()) {
        if (entity is File && entity.path != destFile.path) {
          await entity.delete();
        }
      }
    } catch (_) {}

    final updated = showroomProfileNotifier.value.copyWith(customLogoPath: destFile.path);
    await saveShowroomProfile(updated);
    return destFile.path;
  }

  static Future<void> resetCustomLogoToDefault() async {
    final current = showroomProfileNotifier.value;
    if (current.hasCustomLogo && !kIsWeb) {
      try {
        final f = File(current.customLogoPath!);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await saveShowroomProfile(current.copyWith(clearLogo: true));
  }

  static Future<String?> _pickFileOnWindows({
    required String title,
    required String filter,
  }) async {
    try {
      final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.OpenFileDialog
\$dlg.Title = "$title"
\$dlg.Filter = "$filter"
if (\$dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dlg.FileName
}
''';
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-STA', '-Command', script],
      );
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return null;
  }

  // ---------------------------------------------------------------------------
  // حماية البصمة المعزولة عن قاعدة البيانات (منع التخطي عبر النسخ أو التصفير)
  // ---------------------------------------------------------------------------
  static Future<void> _migrateLegacyBiometricSettingIfNeeded() async {
    final secureVal = await SecurityStorageService.getBool(_biometricEnabledKey);
    if (secureVal == null) {
      final legacyVal = await getSetting(_biometricEnabledKey);
      if (legacyVal != null) {
        await SecurityStorageService.setBool(_biometricEnabledKey, legacyVal == 'true');
      }
    }
    final securePrompted = await SecurityStorageService.getBool(_biometricPromptedKey);
    if (securePrompted == null) {
      final legacyPrompted = await getSetting(_biometricPromptedKey);
      if (legacyPrompted != null) {
        await SecurityStorageService.setBool(_biometricPromptedKey, legacyPrompted == 'true');
      }
    }
  }

  static Future<bool> isBiometricEnabled() async {
    final secure = await SecurityStorageService.getBool(_biometricEnabledKey);
    if (secure != null) return secure;
    final val = await getSetting(_biometricEnabledKey);
    return val == 'true';
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    await SecurityStorageService.setBool(_biometricEnabledKey, enabled);
    try {
      await setSetting(_biometricEnabledKey, enabled ? 'true' : 'false');
    } catch (_) {}
  }

  static Future<bool> wasBiometricPrompted() async {
    final secure = await SecurityStorageService.getBool(_biometricPromptedKey);
    if (secure != null) return secure;
    final val = await getSetting(_biometricPromptedKey);
    return val == 'true';
  }

  static Future<void> markBiometricPrompted() async {
    await SecurityStorageService.setBool(_biometricPromptedKey, true);
    try {
      await setSetting(_biometricPromptedKey, 'true');
    } catch (_) {}
  }

  /// مهلة القفل التلقائي عند العودة من الخلفية بالثواني (افتراضياً 30 ثانية)
  static Future<int> getBiometricTimeoutSeconds() async {
    return (await SecurityStorageService.getInt(_biometricTimeoutKey)) ?? 30;
  }

  static Future<void> setBiometricTimeoutSeconds(int seconds) async {
    await SecurityStorageService.setInt(_biometricTimeoutKey, seconds);
  }

  /// تفعيل تشفير النسخ الاحتياطية المصدرة (مفعّل افتراضياً لحماية بيانات المعرض)
  static Future<bool> isBackupEncryptionEnabled() async {
    final val = await SecurityStorageService.getBool(_backupEncryptKey);
    return val ?? true;
  }

  static Future<void> setBackupEncryptionEnabled(bool enabled) async {
    await SecurityStorageService.setBool(_backupEncryptKey, enabled);
  }

  static Future<bool> isBiometricHardwareSupported() async {
    if (kIsWeb) return false;
    try {
      final auth = LocalAuthentication();
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }
}
