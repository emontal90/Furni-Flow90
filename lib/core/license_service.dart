import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  const LicenseInfo({
    required this.state,
    required this.deviceCode,
    this.licenseKey,
    this.expiresAt,
    this.trialDaysRemaining = 0,
    this.isPermanent = false,
  });

  bool get isActivated => state == LicenseState.activated;
  bool get isUsable => state == LicenseState.activated || state == LicenseState.trial;

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

  /// فحص حالة الترخيص الحالية وتحديث الـ Notifier
  static Future<LicenseInfo> checkStatus() async {
    final deviceCode = await SecurityStorageService.getDeviceCode();
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
      }
    }

    // حساب الفترة التجريبية من أول تشغيل
    final firstRunRaw = await SecurityStorageService.getString('first_run_iso');
    DateTime firstRun;
    if (firstRunRaw != null && DateTime.tryParse(firstRunRaw) != null) {
      firstRun = DateTime.parse(firstRunRaw);
    } else {
      firstRun = DateTime.now();
      await SecurityStorageService.setString('first_run_iso', firstRun.toIso8601String());
    }

    final elapsedDays = DateTime.now().difference(firstRun).inDays;
    final remaining = defaultTrialDays - elapsedDays;

    final info = LicenseInfo(
      state: remaining > 0 ? LicenseState.trial : LicenseState.expired,
      deviceCode: deviceCode,
      trialDaysRemaining: remaining > 0 ? remaining : 0,
      expiresAt: firstRun.add(const Duration(days: defaultTrialDays)),
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
