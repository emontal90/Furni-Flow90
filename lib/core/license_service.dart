import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'backup_crypto.dart';
import 'security_storage_service.dart';

enum LicenseState { activated, trial, expired }

class LicenseInfo {
  final LicenseState state;
  final String deviceCode;
  final String? licenseKey;
  final DateTime? expiresAt;
  final int trialDaysRemaining;
  final bool isPermanent;
  final bool isClockTampered;

  const LicenseInfo({
    required this.state,
    required this.deviceCode,
    this.licenseKey,
    this.expiresAt,
    this.trialDaysRemaining = 0,
    this.isPermanent = false,
    this.isClockTampered = false,
  });

  bool get isActivated => state == LicenseState.activated && !isClockTampered;
  bool get isUsable =>
      (state == LicenseState.activated || state == LicenseState.trial) &&
      !isClockTampered;

  /// حساب عدد الأيام المتبقية في الاشتراك بدقة
  int get daysRemaining {
    if (isPermanent) return 99999;
    if (expiresAt != null) {
      final now = DateTime.now();
      if (now.isAfter(expiresAt!)) return 0;
      final diff = expiresAt!.difference(now);
      return diff.inDays > 0 ? diff.inDays : (diff.inHours > 0 ? 1 : 0);
    }
    return trialDaysRemaining;
  }
}

/// نظام التراخيص التجارية المرتبط بمعرف الجهاز (Device-Bound Offline Licensing)
/// صيغة المفتاح: MTK-<YYYYMMDD أو PERM>-<8_HEX_SIGNATURE>
class LicenseService {
  // مفتاح التوقيع التجاري (يتطابق مع scripts/generate_license.py)
  static const String _signingSecret = 'MobilyaTrack#CommercialLicense#2026!Secret';
  static const int defaultTrialDays = 30;

  static final ValueNotifier<LicenseInfo?> statusNotifier =
      ValueNotifier<LicenseInfo?>(null);

  static String _computeSignature(String deviceCode, String expiryToken) {
    final payload = '${deviceCode.trim().toUpperCase()}|${expiryToken.trim().toUpperCase()}';
    final mac = BackupCrypto.hmacSha256(
      Uint8List.fromList(utf8.encode(_signingSecret)),
      Uint8List.fromList(utf8.encode(payload)),
    );
    return BackupCrypto.toHexUpper(mac).substring(0, 8);
  }

  /// مسار ملف تثبيت التجربة المجانية خارج مجلد التطبيق القابل للحذف
  static Future<File?> _getPersistentAnchorFile() async {
    if (kIsWeb) return null;
    try {
      if (Platform.isWindows) {
        final profile = Platform.environment['USERPROFILE'];
        if (profile != null && profile.isNotEmpty) {
          return File(p.join(profile, '.furniflow_trial_anchor'));
        }
      }
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, '.furniflow_trial_anchor'));
    } catch (_) {
      return null;
    }
  }

  /// قراءة أو تهيئة تاريخ بدء التجربة المجانية مع التوقيع الرياضي لمنع التلاعب
  static Future<DateTime> _resolveFirstRunDate(String deviceCode) async {
    int? earliestMs;

    // 1. فحص المخزن الأمني الداخلي
    final storedAnchor = await SecurityStorageService.getString('trial_anchor');
    if (storedAnchor != null && storedAnchor.contains('|')) {
      final parts = storedAnchor.split('|');
      final ms = int.tryParse(parts[0]);
      if (ms != null && parts.length > 1) {
        final expectedSig = _computeSignature(deviceCode, 'TRIAL:$ms');
        if (parts[1] == expectedSig) {
          earliestMs = ms;
        }
      }
    }

    // 2. فحص الملف المستقل الثابت في نظام التشغيل (يصمد ضد مسح التطبيق بالكامل)
    final anchorFile = await _getPersistentAnchorFile();
    if (anchorFile != null && await anchorFile.exists()) {
      try {
        final raw = (await anchorFile.readAsString()).trim();
        if (raw.contains('|')) {
          final parts = raw.split('|');
          final ms = int.tryParse(parts[0]);
          if (ms != null && parts.length > 1) {
            final expectedSig = _computeSignature(deviceCode, 'TRIAL:$ms');
            if (parts[1] == expectedSig) {
              if (earliestMs == null || ms < earliestMs) {
                earliestMs = ms;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 3. التوافق العكسي مع القيمة القديمة إن وجدت
    if (earliestMs == null) {
      final oldIso = await SecurityStorageService.getString('first_run_iso');
      if (oldIso != null) {
        final parsed = DateTime.tryParse(oldIso);
        if (parsed != null) {
          earliestMs = parsed.millisecondsSinceEpoch;
        }
      }
    }

    // 4. إذا كان تشغيلاً لأول مرة على الإطلاق: تسجيل وتثبيت التوقيع المشفر
    earliestMs ??= DateTime.now().millisecondsSinceEpoch;

    final sig = _computeSignature(deviceCode, 'TRIAL:$earliestMs');
    final anchorData = '$earliestMs|$sig';

    await SecurityStorageService.setString('trial_anchor', anchorData);
    if (anchorFile != null) {
      try {
        await anchorFile.writeAsString(anchorData, flush: true);
      } catch (_) {}
    }

    return DateTime.fromMillisecondsSinceEpoch(earliestMs);
  }

  /// التحقق من سلامة ساعة النظام ومنع تقديم أو تأخير الوقت لتجاوز الفترة التجريبية
  static Future<bool> _verifySystemClock(String deviceCode) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stored = await SecurityStorageService.getString('last_verified_clock');

    if (stored != null && stored.contains('|')) {
      final parts = stored.split('|');
      final lastMs = int.tryParse(parts[0]);
      if (lastMs != null && parts.length > 1) {
        final expectedSig = _computeSignature(deviceCode, 'CLOCK:$lastMs');
        if (parts[1] == expectedSig) {
          // إذا كان الوقت الحالي أقل من آخر وقت مسجل بأكثر من 5 دقائق: تلاعب بساعة النظام
          if (nowMs < (lastMs - 300000)) {
            return false;
          }
        }
      }
    }

    // تحديث الطابع الزمني الموثق
    final sig = _computeSignature(deviceCode, 'CLOCK:$nowMs');
    await SecurityStorageService.setString('last_verified_clock', '$nowMs|$sig');
    return true;
  }

  /// توليد مفتاح ترخيص صالح (للاختبارات أو التوليد الداخلي)
  static String generateKeyForDevice(String deviceCode, {String expiryToken = 'PERM'}) {
    final cleanExp = expiryToken.trim().toUpperCase();
    final sig = _computeSignature(deviceCode, cleanExp);
    return 'MTK-$cleanExp-$sig';
  }

  /// التحقق الرياضي من صحة مفتاح الترخيص المرتبط بجهاز محدد
  static ({bool valid, bool isPermanent, DateTime? expiresAt, String? error}) validateKey({
    required String deviceCode,
    required String rawKey,
  }) {
    final cleaned = rawKey.trim().toUpperCase();
    final parts = cleaned.split('-');
    if (parts.length != 3 || parts[0] != 'MTK') {
      return (valid: false, isPermanent: false, expiresAt: null, error: 'صيغة كود التفعيل غير صحيحة.');
    }

    final expiryToken = parts[1];
    final providedSig = parts[2];
    final expectedSig = _computeSignature(deviceCode, expiryToken);

    if (providedSig.length != 8 ||
        !BackupCrypto.constantTimeEquals(
          Uint8List.fromList(utf8.encode(providedSig)),
          Uint8List.fromList(utf8.encode(expectedSig)),
        )) {
      return (valid: false, isPermanent: false, expiresAt: null, error: 'كود التفعيل غير مطابق لمعرف هذا الجهاز.');
    }

    if (expiryToken == 'PERM') {
      return (valid: true, isPermanent: true, expiresAt: null, error: null);
    }

    if (expiryToken.length != 8 || int.tryParse(expiryToken) == null) {
      return (valid: false, isPermanent: false, expiresAt: null, error: 'تاريخ انتهاء الترخيص غير صالح.');
    }

    final y = int.parse(expiryToken.substring(0, 4));
    final m = int.parse(expiryToken.substring(4, 6));
    final d = int.parse(expiryToken.substring(6, 8));
    final expiryDate = DateTime(y, m, d, 23, 59, 59);
    if (DateTime.now().isAfter(expiryDate)) {
      return (valid: false, isPermanent: false, expiresAt: expiryDate, error: 'انتهت صلاحية كود التفعيل هذا.');
    }

    return (valid: true, isPermanent: false, expiresAt: expiryDate, error: null);
  }

  /// فحص حالة الترخيص الحالية وتحديث الـ Notifier (يعمل أوفلاين 100% وبأعلى سرعة وأمان)
  static Future<LicenseInfo> checkStatus() async {
    final deviceCode = await SecurityStorageService.getDeviceCode();
    final clockValid = await _verifySystemClock(deviceCode);

    if (!clockValid) {
      final info = LicenseInfo(
        state: LicenseState.expired,
        deviceCode: deviceCode,
        isClockTampered: true,
      );
      statusNotifier.value = info;
      return info;
    }

    final storedKey = await SecurityStorageService.getString('license_key');

    if (storedKey != null && storedKey.trim().isNotEmpty) {
      final res = validateKey(deviceCode: deviceCode, rawKey: storedKey);
      if (res.valid) {
        final info = LicenseInfo(
          state: LicenseState.activated,
          deviceCode: deviceCode,
          licenseKey: storedKey.trim().toUpperCase(),
          expiresAt: res.expiresAt,
          isPermanent: res.isPermanent,
        );
        statusNotifier.value = info;
        return info;
      } else if (res.expiresAt != null && DateTime.now().isAfter(res.expiresAt!)) {
        // إذا كان هناك مفتاح ترخيص وانتهت صلاحيته، يُقفل البرنامج فوراً كترخيص منتهي الصلاحية
        final info = LicenseInfo(
          state: LicenseState.expired,
          deviceCode: deviceCode,
          licenseKey: storedKey.trim().toUpperCase(),
          expiresAt: res.expiresAt,
          isPermanent: false,
        );
        statusNotifier.value = info;
        return info;
      }
    }

    // حساب الفترة التجريبية الموثقة برقم العتاد الثابت (30 يوماً من أول تشغيل غير قابلة للتجديد)
    final firstRun = await _resolveFirstRunDate(deviceCode);
    final now = DateTime.now();
    final expiryDate = firstRun.add(const Duration(days: defaultTrialDays));
    final diff = expiryDate.difference(now);
    final remainingDays = diff.inDays > 0 ? diff.inDays : (diff.inSeconds > 0 ? 1 : 0);
    final isTrialActive = now.isBefore(expiryDate) && remainingDays > 0;

    final info = LicenseInfo(
      state: isTrialActive ? LicenseState.trial : LicenseState.expired,
      deviceCode: deviceCode,
      trialDaysRemaining: remainingDays,
      expiresAt: expiryDate,
    );
    statusNotifier.value = info;
    return info;
  }

  /// تفعيل البرنامج بكود ترخيص تجاري
  static Future<String?> activateWithKey(String rawKey) async {
    final deviceCode = await SecurityStorageService.getDeviceCode();
    final res = validateKey(deviceCode: deviceCode, rawKey: rawKey);
    if (!res.valid) {
      return res.error ?? 'كود التفعيل غير صالح.';
    }
    await SecurityStorageService.setString('license_key', rawKey.trim().toUpperCase());
    await checkStatus();
    return null;
  }
}
