import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'backup_crypto.dart';

/// مخزن أمني منفصل تماماً عن قاعدة البيانات `furniture_erp.db`
/// يضمن عدم تعطل البصمة أو مسح الترخيص التجاري عند استعادة نسخة احتياطية أو إعادة ضبط المصنع
class SecurityStorageService {
  static const MethodChannel _securityChannel =
      MethodChannel('com.furniflow.erp/security');

  static const String _fileName = 'mobilya_track_secure.json';
  static Map<String, dynamic>? _memoryCache;

  static Future<File?> _getStoreFile() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File(p.join(dir.path, _fileName));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _readAll() async {
    if (_memoryCache != null) return Map<String, dynamic>.from(_memoryCache!);
    final file = await _getStoreFile();
    if (file == null) {
      _memoryCache = {};
      return {};
    }
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        String raw;
        if (BackupCrypto.isEncryptedBytes(bytes)) {
          final plain = BackupCrypto.decryptBytes(
            bytes,
            passphrase: BackupCrypto.deriveDeviceBackupKey('LOCAL_SECURE_STORE'),
          );
          raw = utf8.decode(plain);
        } else {
          raw = utf8.decode(bytes);
        }
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _memoryCache = Map<String, dynamic>.from(decoded);
          return Map<String, dynamic>.from(_memoryCache!);
        }
      }
    } catch (_) {}
    _memoryCache = {};
    return {};
  }

  static Future<void> _writeAll(Map<String, dynamic> data) async {
    _memoryCache = Map<String, dynamic>.from(data);
    final file = await _getStoreFile();
    if (file == null) return;
    try {
      final plainBytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      final encrypted = BackupCrypto.encryptBytes(
        plainBytes,
        passphrase: BackupCrypto.deriveDeviceBackupKey('LOCAL_SECURE_STORE'),
      );
      await file.writeAsBytes(encrypted, flush: true);
    } catch (_) {}
  }

  static Future<String?> getString(String key) async {
    final map = await _readAll();
    final val = map[key];
    return val?.toString();
  }

  static Future<void> setString(String key, String? value) async {
    final map = await _readAll();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    await _writeAll(map);
  }

  static Future<bool?> getBool(String key) async {
    final map = await _readAll();
    final val = map[key];
    if (val is bool) return val;
    if (val is String) {
      if (val == 'true') return true;
      if (val == 'false') return false;
    }
    return null;
  }

  static Future<void> setBool(String key, bool value) async {
    final map = await _readAll();
    map[key] = value;
    await _writeAll(map);
  }

  static Future<void> remove(String key) async {
    final map = await _readAll();
    map.remove(key);
    await _writeAll(map);
  }

  static Future<int?> getInt(String key) async {
    final map = await _readAll();
    final val = map[key];
    if (val is int) return val;
    return int.tryParse(val?.toString() ?? '');
  }

  static Future<void> setInt(String key, int value) async {
    final map = await _readAll();
    map[key] = value;
    await _writeAll(map);
  }

  /// استخراج بصمة الجهاز الفريدة (تُستخدم لربط الترخيص التجاري بالجهاز)
  /// تضمن ثبات المعرف لكل جهاز حتى لو قام المستخدم بحذف التطبيق وإعادة تنزيله
  static Future<String> getDeviceCode() async {
    final cached = await getString('device_code');
    if (cached != null && cached.isNotEmpty) return cached;

    // محاولة قراءة المعرف المحفوظ في مسار النظام الدائم خارج مجلد التطبيق القابل للحذف
    if (!kIsWeb && Platform.isWindows) {
      try {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final fallbackFile = File(p.join(userProfile, '.furniflow_device_id'));
          if (await fallbackFile.exists()) {
            final savedCode = (await fallbackFile.readAsString()).trim();
            if (savedCode.isNotEmpty && savedCode.startsWith('MT-')) {
              await setString('device_code', savedCode);
              return savedCode;
            }
          }
        }
      } catch (_) {}
    }

    String rawHardwareId = '';
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidId = await _securityChannel.invokeMethod<String>('getDeviceId');
        if (androidId != null && androidId.trim().isNotEmpty) {
          rawHardwareId = 'AND:${androidId.trim()}';
        }
      } catch (_) {}
    } else if (!kIsWeb && Platform.isWindows) {
      // قراءة MachineGuid الفريد والثابت لنظام ويندوز من سجل النظام (Registry)
      String machineGuid = '';
      try {
        final result = Process.runSync('reg', [
          'query',
          r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ]);
        if (result.exitCode == 0) {
          final out = result.stdout.toString();
          final match = RegExp(r'MachineGuid\s+REG_\w+\s+([a-fA-F0-9-]+)').firstMatch(out);
          if (match != null && match.group(1) != null) {
            machineGuid = match.group(1)!.trim();
          }
        }
      } catch (_) {}

      final host = Platform.environment['COMPUTERNAME'] ?? '';
      final user = Platform.environment['USERNAME'] ?? '';
      final proc = Platform.environment['PROCESSOR_IDENTIFIER'] ?? '';

      if (machineGuid.isNotEmpty) {
        rawHardwareId = 'WIN:GUID:$machineGuid';
      } else if (host.isNotEmpty) {
        rawHardwareId = 'WIN:$host:$user:$proc';
      }
    }

    if (rawHardwareId.isEmpty) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
      rawHardwareId = 'GEN:${base64Url.encode(bytes)}';
    }

    final hash = BackupCrypto.sha256(Uint8List.fromList(utf8.encode('MobilyaTrack|$rawHardwareId')));
    final hex = BackupCrypto.toHexUpper(hash).substring(0, 12);
    final formatted = 'MT-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
    await setString('device_code', formatted);

    // حفظ نسخة احتياطية في ملف ثابت لضمان عدم تغيره عند مسح التطبيق
    if (!kIsWeb && Platform.isWindows) {
      try {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final fallbackFile = File(p.join(userProfile, '.furniflow_device_id'));
          await fallbackFile.writeAsString(formatted, flush: true);
        }
      } catch (_) {}
    }

    return formatted;
  }

  /// مسح الكاش في الذاكرة (مفيد للاختبارات فقط)
  static void clearMemoryCacheForTests() {
    _memoryCache = null;
  }
}
