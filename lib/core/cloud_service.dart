import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'backup_crypto.dart';
import 'backup_service.dart';
import 'db_helper.dart';
import 'license_service.dart';
import 'security_storage_service.dart';

enum PaymentMethod {
  vodafoneCash,
  instapay,
}

class SubscriptionPlan {
  final String id;
  final String title;
  final String durationText;
  final int days;
  final int price;
  final String badgeText;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.durationText,
    required this.days,
    required this.price,
    this.badgeText = '',
    this.isPopular = false,
  });

  static const List<SubscriptionPlan> plans = [
    SubscriptionPlan(
      id: 'monthly',
      title: 'باقة شهر',
      durationText: '30 يوم كاملة',
      days: 30,
      price: 300,
      badgeText: 'المرونة التامة',
    ),
    SubscriptionPlan(
      id: 'half_yearly',
      title: 'باقة 6 شهور',
      durationText: '180 يوماً',
      days: 180,
      price: 1800,
      badgeText: 'الأكثر طلباً',
      isPopular: true,
    ),
    SubscriptionPlan(
      id: 'yearly',
      title: 'باقة عام كامل',
      durationText: '365 يوماً',
      days: 365,
      price: 3500,
      badgeText: 'أفضل توفير',
    ),
  ];
}

class CloudSubscriptionData {
  final String? id;
  final String deviceCode;
  final String status; // pending, active, paused, expired
  final String? senderPhone;
  final String? referenceNo;
  final String? paymentMethod;
  final String? planType;
  final int planDays;
  final num amount;
  final String? licenseKey;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const CloudSubscriptionData({
    this.id,
    required this.deviceCode,
    required this.status,
    this.senderPhone,
    this.referenceNo,
    this.paymentMethod,
    this.planType,
    this.planDays = 30,
    this.amount = 0,
    this.licenseKey,
    this.startsAt,
    this.expiresAt,
    this.createdAt,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isPaused => status == 'paused';
  bool get isExpired => status == 'expired';

  int get daysRemaining {
    if (expiresAt == null) return 0;
    final diffSec = expiresAt!.difference(DateTime.now()).inSeconds;
    return diffSec > 0 ? (diffSec / 86400).ceil() : 0;
  }

  factory CloudSubscriptionData.fromJson(Map<String, dynamic> json) {
    return CloudSubscriptionData(
      id: json['id']?.toString(),
      deviceCode: json['device_code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      senderPhone: json['sender_phone']?.toString(),
      referenceNo: json['reference_no']?.toString(),
      paymentMethod: json['payment_method']?.toString(),
      planType: json['plan_type']?.toString(),
      planDays: int.tryParse(json['plan_days']?.toString() ?? '') ?? 30,
      amount: num.tryParse(json['amount']?.toString() ?? '') ?? 0,
      licenseKey: json['license_key']?.toString(),
      startsAt: json['starts_at'] != null
          ? DateTime.tryParse(json['starts_at'].toString())
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }
}

class CloudBackupItem {
  final String id;
  final String deviceCode;
  final String fileName;
  final String storagePath;
  final int fileSizeBytes;
  final String fileSizeFormatted;
  final bool isAuto;
  final DateTime createdAt;

  const CloudBackupItem({
    required this.id,
    required this.deviceCode,
    required this.fileName,
    required this.storagePath,
    required this.fileSizeBytes,
    required this.fileSizeFormatted,
    this.isAuto = false,
    required this.createdAt,
  });

  factory CloudBackupItem.fromJson(Map<String, dynamic> json) {
    return CloudBackupItem(
      id: json['id']?.toString() ?? '',
      deviceCode: json['device_code']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      storagePath: json['storage_path']?.toString() ?? '',
      fileSizeBytes:
          int.tryParse(json['file_size_bytes']?.toString() ?? '') ?? 0,
      fileSizeFormatted: json['file_size_formatted']?.toString() ?? '0 KB',
      isAuto: json['is_auto'] == true || json['is_auto'] == 'true',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class CloudService {
  static const String defaultSupabaseUrl =
      'https://httdsktwfnrkhhlcznzo.supabase.co';
  // يتم تمرير المفتاح بشكل آمن أثناء البناء عبر --dart-define دون دمج أو كتابة أي مفتاح في الكود المصدري
  static const String _compileTimeAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String bucketName = 'furniflow-backups';
  static const String approvedPaymentNumber = '01094085228';
  static const int maxCloudBackups = 5;

  static final ValueNotifier<CloudSubscriptionData?> cloudStatusNotifier =
      ValueNotifier<CloudSubscriptionData?>(null);

  /// استرجاع مفتاح Anon Key بأعلى معايير الأمان دون كتابة أي مفتاح صريح في الكود
  static Future<String> getAnonKey() async {
    // 1. قراءة المفتاح المحقون أثناء البناء من GitHub Actions عبر --dart-define
    if (_compileTimeAnonKey.isNotEmpty) {
      return _compileTimeAnonKey;
    }

    // 2. قراءة المفتاح من المخزن الأمني المشفر محلياً
    final custom = await SecurityStorageService.getString('supabase_anon_key');
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();

    // 3. أثناء التطوير المحلي: قراءة المفتاح من الملف المستثنى تماماً في .gitignore
    if (!kIsWeb) {
      try {
        final localConfigFile = File('portal/config.js');
        if (await localConfigFile.exists()) {
          final content = await localConfigFile.readAsString();
          final match =
              RegExp(r'SUPABASE_ANON_KEY:\s*["\x27]([^"\x27]+)["\x27]')
                  .firstMatch(content);
          if (match != null && match.group(1) != null) {
            final key = match.group(1)!.trim();
            if (key.isNotEmpty && !key.startsWith('PASTE_')) {
              return key;
            }
          }
        }
      } catch (_) {}
    }

    return '';
  }

  /// تعيين مفتاح Anon Key مخصص
  static Future<void> setAnonKey(String key) async {
    await SecurityStorageService.setString('supabase_anon_key', key.trim());
  }

  /// استرجاع رابط Supabase المخزن أو الافتراضي
  static Future<String> getSupabaseUrl() async {
    final custom = await SecurityStorageService.getString('supabase_url');
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return defaultSupabaseUrl;
  }

  static Future<Map<String, String>> _getHeaders({bool isPost = false}) async {
    final anonKey = await getAnonKey();
    final headers = {
      'apikey': anonKey,
      'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
    };
    if (isPost) {
      headers['Prefer'] = 'return=representation';
    }
    return headers;
  }

  // -------------------------------------------------------------
  // 1. نظام الاشتراكات والتفعيل السحابي
  // -------------------------------------------------------------

  /// إرسال طلب اشتراك جديد إلى سوبا بيز
  static Future<({bool success, String? error, CloudSubscriptionData? data})>
      submitSubscriptionRequest({
    required String deviceCode,
    required String senderPhone,
    required String referenceNo,
    required PaymentMethod paymentMethod,
    required SubscriptionPlan plan,
  }) async {
    try {
      final baseUrl = await getSupabaseUrl();
      final headers = await _getHeaders(isPost: true);

      final payload = {
        'device_code': deviceCode.trim().toUpperCase(),
        'sender_phone': senderPhone.trim(),
        'reference_no': referenceNo.trim(),
        'payment_method': paymentMethod == PaymentMethod.vodafoneCash
            ? 'vodafone_cash'
            : 'instapay',
        'plan_type': plan.id,
        'plan_days': plan.days,
        'amount': plan.price,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse('$baseUrl/rest/v1/app_subscriptions'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        Map<String, dynamic> itemMap;
        if (decoded is List && decoded.isNotEmpty) {
          itemMap = decoded.first as Map<String, dynamic>;
        } else if (decoded is Map<String, dynamic>) {
          itemMap = decoded;
        } else {
          itemMap = payload;
        }
        final subData = CloudSubscriptionData.fromJson(itemMap);
        cloudStatusNotifier.value = subData;
        return (success: true, error: null, data: subData);
      } else {
        return (
          success: false,
          error:
              'فشل إرسال الطلب: رمز الاستجابة (${response.statusCode}) - ${response.body}',
          data: null,
        );
      }
    } catch (e) {
      return (
        success: false,
        error: 'حدث خطأ أثناء الاتصال بالخادم السحابي: $e',
        data: null,
      );
    }
  }

  /// الاستعلام عن حالة اشتراك الجهاز في سوبا بيز وتحديث ترخيص التطبيق فوراً
  static Future<CloudSubscriptionData?> checkAndSyncSubscriptionStatus(
      String deviceCode) async {
    try {
      final baseUrl = await getSupabaseUrl();
      final headers = await _getHeaders();
      final cleanDevice = deviceCode.trim().toUpperCase();

      final url = Uri.parse(
        '$baseUrl/rest/v1/rpc/get_device_subscription',
      );

      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({'p_device_code': cleanDevice}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty) {
          final firstMap = decoded.first as Map<String, dynamic>;
          final item = CloudSubscriptionData.fromJson(firstMap);
          cloudStatusNotifier.value = item;

          // فحص هل قامت الإدارة بإعادة تمكين التجربة من قاعدة البيانات
          final notes = (firstMap['notes'] ?? '').toString();
          if (notes.contains('RESET_TRIAL')) {
            await LicenseService.resetTrial();
          }

          // إذا كان الاشتراك نشطاً ويحتوي على مفتاح ترخيص، نقوم بتفعيله تلقائياً
          if (item.isActive &&
              item.licenseKey != null &&
              item.licenseKey!.isNotEmpty) {
            await LicenseService.markTrialConsumed();
            await LicenseService.activateWithKey(item.licenseKey!);
          } else if (item.isPaused || item.isExpired) {
            // في حالة إيقاف الاشتراك أو انتهائه: استهلاك التجربة ومسح المفتاح لإغلاق البرنامج
            await LicenseService.markTrialConsumed();
            await SecurityStorageService.setString('license_key', null);
            await LicenseService.checkStatus();
          }
          return item;
        } else if (decoded is List && decoded.isEmpty) {
          // إذا تم حذف الاشتراك من البورتال
          cloudStatusNotifier.value = null;
          final wasConsumed = await LicenseService.isTrialConsumed();
          final storedKey = await SecurityStorageService.getString('license_key');
          if (wasConsumed || (storedKey != null && storedKey.isNotEmpty)) {
            // حذف الاشتراك يؤدي لتشفير وإغلاق البرنامج
            await LicenseService.markTrialConsumed();
            await SecurityStorageService.setString('license_key', null);
            await LicenseService.checkStatus();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Timer? _realtimeSyncTimer;
  static bool _isSyncing = false;

  /// بدء حلقة المزامنة اللحظية المستمرة للاشتراكات في الخلفية
  /// تقوم بالتحقق اللحظي مع السحابة دورياً لتطبيق الإيقاف، التشفير، التفعيل، أو تعديل الأيام فوراً
  static void startRealtimeSyncLoop({Duration interval = const Duration(minutes: 5)}) {
    _realtimeSyncTimer?.cancel();
    triggerRealtimeSyncNow();
    _realtimeSyncTimer = Timer.periodic(interval, (_) {
      triggerRealtimeSyncNow();
    });
  }

  /// إيقاف حلقة المزامنة اللحظية
  static void stopRealtimeSyncLoop() {
    _realtimeSyncTimer?.cancel();
    _realtimeSyncTimer = null;
  }

  /// تنفيذ مزامنة فورية عاجلة مع السحابة
  static Future<void> triggerRealtimeSyncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final code = await SecurityStorageService.getDeviceCode();
      if (code.isNotEmpty) {
        await checkAndSyncSubscriptionStatus(code);
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
  }

  // -------------------------------------------------------------
  // 2. نظام النسخ الاحتياطي السحابي المشفر
  // -------------------------------------------------------------

  /// التحقق من صلاحية المستخدم لرفع واستعادة النسخ السحابية
  static Future<bool> isUserEligibleForCloudBackup() async {
    final lic = await LicenseService.checkStatus();
    return lic.isUsable;
  }

  /// رفع نسخة احتياطية مشفرة إلى سوبا بيز (يدوية أو تلقائية)
  static Future<({bool success, String message, CloudBackupItem? item})>
      uploadEncryptedBackup({
    bool isAuto = false,
  }) async {
    if (kIsWeb) {
      return (
        success: false,
        message: 'النسخ السحابي غير مدعوم على الويب',
        item: null
      );
    }

    try {
      final isEligible = await isUserEligibleForCloudBackup();
      if (!isEligible) {
        return (
          success: false,
          message:
              'خدمة النسخ السحابي متاحة للمشتركين فقط. يرجى تفعيل الاشتراك أولاً.',
          item: null,
        );
      }

      final db = await DBHelper.instance.database;
      try {
        await db.execute('PRAGMA optimize');
        await db.execute('VACUUM');
      } catch (_) {}

      final dbFile = await BackupService.getDatabaseFile();
      if (!await dbFile.exists()) {
        return (
          success: false,
          message: 'قاعدة البيانات غير موجودة',
          item: null
        );
      }

      final deviceCode = await SecurityStorageService.getDeviceCode();
      final now = DateTime.now();
      final dateStr = intl.DateFormat('yyyy-MM-dd').format(now);
      final timeStr = intl.DateFormat('HH-mm-ss').format(now);
      final millis = now.millisecondsSinceEpoch % 10000;

      final fileName = isAuto
          ? 'cloud_auto_${deviceCode}_${dateStr}_$timeStr.mtbk'
          : 'cloud_manual_${deviceCode}_${dateStr}_${timeStr}_$millis.mtbk';

      final storageRelativePath = '$deviceCode/$fileName';

      // قراءة بايتات قاعدة البيانات وتشفيرها تشفيراً عسكرياً قبل الإرسال (AES-256)
      final rawBytes = await dbFile.readAsBytes();
      final encryptedBytes = BackupCrypto.encryptBytes(
        rawBytes,
        passphrase: BackupCrypto.deriveDeviceBackupKey(deviceCode),
      );

      final baseUrl = await getSupabaseUrl();
      final anonKey = await getAnonKey();

      if (anonKey.isEmpty) {
        return (
          success: false,
          message: 'لم يتم العثور على مفتاح الربط السحابي (Supabase Anon Key).',
          item: null,
        );
      }

      // 1. رفع الملف إلى Supabase Storage
      final storageUrl = Uri.parse(
        '$baseUrl/storage/v1/object/$bucketName/$storageRelativePath',
      );

      // حذف أي ملف قديم بنفس المسار إن وُجد لتفادي خطأ تصريح التحديث (Upsert RLS)
      try {
        await http.delete(storageUrl, headers: {
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        }).timeout(const Duration(seconds: 10));
      } catch (_) {}

      final storageResponse = await http
          .post(
            storageUrl,
            headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $anonKey',
              'Content-Type': 'application/octet-stream',
              'x-upsert': 'true',
            },
            body: encryptedBytes,
          )
          .timeout(const Duration(seconds: 45));

      if (storageResponse.statusCode < 200 ||
          storageResponse.statusCode >= 300) {
        String detail = '';
        try {
          final errJson = jsonDecode(storageResponse.body);
          detail = errJson['message'] ?? errJson['error'] ?? '';
        } catch (_) {}
        return (
          success: false,
          message:
              'فشل رفع الملف إلى مساحة التخزين السحابي (${storageResponse.statusCode})${detail.isNotEmpty ? ": $detail" : ""}',
          item: null,
        );
      }

      // حساب الحجم المنسق
      final sizeBytes = encryptedBytes.length;
      final sizeFormatted = sizeBytes < 1024 * 1024
          ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
          : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';

      // 2. تسجيل النسخة عبر دالة RPC مقيدة برقم الجهاز
      final insertHeaders = await _getHeaders(isPost: true);
      final rpcPayload = {
        'p_device_code': deviceCode,
        'p_file_name': fileName,
        'p_storage_path': storageRelativePath,
        'p_file_size_bytes': sizeBytes,
        'p_file_size_formatted': sizeFormatted,
        'p_is_auto': isAuto,
      };

      final dbInsertResponse = await http
          .post(
            Uri.parse('$baseUrl/rest/v1/rpc/register_device_backup'),
            headers: insertHeaders,
            body: jsonEncode(rpcPayload),
          )
          .timeout(const Duration(seconds: 15));

      CloudBackupItem? createdItem;
      if (dbInsertResponse.statusCode >= 200 &&
          dbInsertResponse.statusCode < 300) {
        final decoded = jsonDecode(dbInsertResponse.body);
        if (decoded is Map<String, dynamic>) {
          createdItem = CloudBackupItem.fromJson(decoded);
        } else if (decoded is List && decoded.isNotEmpty) {
          createdItem =
              CloudBackupItem.fromJson(decoded.first as Map<String, dynamic>);
        }
      }

      // 3. فرض الحد الأقصى 5 ملفات فقط وحذف الأقدم تلقائياً
      await enforceCloudBackupLimit(deviceCode);

      // تسجيل تاريخ آخر نسخ سحابي ناجح
      await SecurityStorageService.setString(
        'last_cloud_backup_date',
        dateStr,
      );

      return (
        success: true,
        message:
            'تم رفع النسخة الاحتياطية المشفرة سحابياً بنجاح ($sizeFormatted)',
        item: createdItem,
      );
    } catch (e) {
      return (
        success: false,
        message: 'حدث خطأ أثناء النسخ السحابي: $e',
        item: null,
      );
    }
  }

  /// جلب قائمة النسخ السحابية المتاحة لهذا الجهاز
  static Future<List<CloudBackupItem>> fetchCloudBackups(
      String deviceCode) async {
    try {
      final baseUrl = await getSupabaseUrl();
      final headers = await _getHeaders();
      final cleanDevice = deviceCode.trim().toUpperCase();

      final url = Uri.parse(
        '$baseUrl/rest/v1/rpc/list_device_backups',
      );

      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode({'p_device_code': cleanDevice}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .map((e) => CloudBackupItem.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// تنزيل نسخة احتياطية من السحابة وفك تشفيرها واستعادتها
  static Future<({bool success, String message})> restoreFromCloud(
      CloudBackupItem item) async {
    if (kIsWeb) {
      return (success: false, message: 'الاستعادة غير مدعومة على الويب');
    }

    try {
      final baseUrl = await getSupabaseUrl();
      final anonKey = await getAnonKey();

      // تنزيل الملف المشفر من Supabase Storage
      final downloadUrl = Uri.parse(
        '$baseUrl/storage/v1/object/$bucketName/${item.storagePath}',
      );

      final response = await http.get(downloadUrl, headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      }).timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return (
          success: false,
          message: 'تعذر تحميل النسخة من السحابة (رمز ${response.statusCode})',
        );
      }

      final downloadedEncryptedBytes = response.bodyBytes;

      // فك التشفير
      Uint8List plainDbBytes;
      if (BackupCrypto.isEncryptedBytes(downloadedEncryptedBytes)) {
        try {
          plainDbBytes = BackupCrypto.decryptBytes(
            downloadedEncryptedBytes,
            passphrase: BackupCrypto.deriveDeviceBackupKey(item.deviceCode),
          );
        } catch (_) {
          // التوافق العكسي مع النسخ السحابية القديمة
          plainDbBytes = BackupCrypto.decryptBytes(downloadedEncryptedBytes);
        }
      } else {
        plainDbBytes = downloadedEncryptedBytes;
      }

      // حفظ النسخة المستعادة في ملف مؤقت
      final tempDir = await getTemporaryDirectory();
      final tempRestoreFile = File(
        p.join(tempDir.path,
            'restored_${DateTime.now().millisecondsSinceEpoch}.db'),
      );
      await tempRestoreFile.writeAsBytes(plainDbBytes, flush: true);

      // تنفيذ الاستعادة عبر BackupService الموحد
      final ok = await BackupService.restoreBackup(tempRestoreFile.path);

      try {
        if (await tempRestoreFile.exists()) await tempRestoreFile.delete();
      } catch (_) {}

      if (ok) {
        return (
          success: true,
          message:
              'تمت استعادة النسخة الاحتياطية بنجاح من السحابة وتحديث البيانات!'
        );
      } else {
        return (
          success: false,
          message: 'فشلت معالجة ملف قاعدة البيانات المستعاد'
        );
      }
    } catch (e) {
      return (
        success: false,
        message: 'حدث خطأ أثناء استعادة النسخة من السحابة: $e'
      );
    }
  }

  /// حذف نسخة سحابية محددة
  static Future<bool> deleteCloudBackup(CloudBackupItem item) async {
    try {
      final baseUrl = await getSupabaseUrl();
      final anonKey = await getAnonKey();
      final headers = await _getHeaders();

      // 1. حذف الملف من مساحة التخزين
      final storageUrl = Uri.parse(
        '$baseUrl/storage/v1/object/$bucketName/${item.storagePath}',
      );
      await http.delete(storageUrl, headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      });

      // 2. حذف السجل عبر دالة RPC مقيدة برقم الجهاز
      final dbUrl = Uri.parse(
        '$baseUrl/rest/v1/rpc/delete_device_backup',
      );
      final resp = await http.post(
        dbUrl,
        headers: headers,
        body: jsonEncode({
          'p_id': item.id,
          'p_device_code': item.deviceCode,
        }),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// التأكد من وجود 5 ملفات فقط كحد أقصى لكل جهاز على السحابة وحذف الأقدم
  static Future<void> enforceCloudBackupLimit(String deviceCode) async {
    try {
      final backups = await fetchCloudBackups(deviceCode);
      if (backups.length <= maxCloudBackups) return;

      // النسخ مرتبة تنازلياً حسب التاريخ الأحدث، نحذف ما زاد عن 5
      for (int i = maxCloudBackups; i < backups.length; i++) {
        await deleteCloudBackup(backups[i]);
      }
    } catch (_) {}
  }

  /// التحقق اليومي التلقائي وإجراء نسخ احتياطي سحابي صامت (مرة واحدة يومياً وبحد أقصى 5 ملفات)
  static Future<void> performDailySilentCloudBackup() async {
    if (kIsWeb) return;
    try {
      final isEligible = await isUserEligibleForCloudBackup();
      if (!isEligible) return;

      final todayStr = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastDate =
          await SecurityStorageService.getString('last_cloud_backup_date');

      if (lastDate != todayStr) {
        // إجراء نسخ سحابي صامت
        await uploadEncryptedBackup(isAuto: true);
      }
    } catch (_) {}
  }
}
