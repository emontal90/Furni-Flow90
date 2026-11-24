import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'app_events.dart';
import 'app_settings_service.dart';
import 'backup_crypto.dart';
import 'cloud_service.dart';
import 'db_helper.dart';

class BackupService {
  static const int maxBackups = 5;
  static const MethodChannel _transferChannel =
      MethodChannel('com.furniflow.erp/backup_transfer');

  /// مجلد حفظ النسخ الاحتياطية على الموبايل والكمبيوتر
  static Future<Directory> getBackupDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'FurnitureBackups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// مسار ملف قاعدة البيانات الفعلي
  static Future<File> getDatabaseFile() async {
    final dbPath = await getDatabasesPath();
    return File(p.join(dbPath, 'furniture_erp.db'));
  }

  /// حجم قاعدة البيانات الفعلي المنسق (بالكيلوبايت أو الميجابايت)
  static Future<String> getDatabaseSize() async {
    try {
      final file = await getDatabaseFile();
      if (await file.exists()) {
        final bytes = await file.length();
        if (bytes < 1024 * 1024) {
          return '${(bytes / 1024).toStringAsFixed(1)} KB';
        } else {
          return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
        }
      }
    } catch (_) {}
    return '0 KB';
  }

  /// إنشاء نسخة احتياطية (يدوية أو تلقائية أو قبل الأرشفة)
  static Future<String> createBackup({
    bool isAuto = false,
    String? prefix,
  }) async {
    if (kIsWeb) return 'النسخ الاحتياطي غير متاح على الويب';

    try {
      final db = await DBHelper.instance.database;
      try {
        await db.execute('PRAGMA optimize');
        await db.execute('VACUUM');
      } catch (_) {}

      final srcFile = await getDatabaseFile();
      if (!await srcFile.exists()) return 'قاعدة البيانات غير موجودة بعد';

      final backupDir = await getBackupDir();
      final dateStr = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
      final timeStr = intl.DateFormat('HH-mm-ss').format(DateTime.now());

      String fileName;
      if (prefix != null && prefix.isNotEmpty) {
        fileName = '${prefix}_${dateStr}_$timeStr.db';
      } else if (isAuto) {
        fileName = 'auto_backup_$dateStr.db';
      } else {
        fileName = 'manual_backup_${dateStr}_$timeStr.db';
      }

      final destPath = p.join(backupDir.path, fileName);
      await srcFile.copy(destPath);

      await enforceMaxBackupLimit(backupDir);
      return destPath;
    } catch (e) {
      return 'فشل إنشاء النسخة الاحتياطية: $e';
    }
  }

  /// التحقق من وجود نسخة احتياطية لليوم وإنشائها تلقائياً
  static Future<void> performDailyAutoBackup() async {
    if (kIsWeb) return;
    try {
      final backupDir = await getBackupDir();
      final dateStr = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
      final todayBackup = File(p.join(backupDir.path, 'auto_backup_$dateStr.db'));
      if (!await todayBackup.exists()) {
        await createBackup(isAuto: true);
      } else {
        await enforceMaxBackupLimit(backupDir);
      }
    } catch (_) {}
  }

  /// التأكد من أن إجمالي ملفات النسخ الاحتياطية لا يتجاوز [maxCount] وحذف الأقدم
  static Future<void> enforceMaxBackupLimit(
    Directory backupDir, {
    int maxCount = maxBackups,
  }) async {
    try {
      if (!await backupDir.exists()) return;
      final dbFiles = backupDir
          .listSync()
          .whereType<File>()
          .where((f) {
            final lower = f.path.toLowerCase();
            return lower.endsWith('.db') || lower.endsWith('.mtbk');
          })
          .toList();

      if (dbFiles.length <= maxCount) return;

      dbFiles.sort((a, b) {
        final modCmp = b.statSync().modified.compareTo(a.statSync().modified);
        if (modCmp != 0) return modCmp;
        return p.basename(b.path).compareTo(p.basename(a.path));
      });

      for (int i = maxCount; i < dbFiles.length; i++) {
        try {
          await dbFiles[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// جلب قائمة جميع النسخ الاحتياطية مرتبة من الأحدث للأقدم
  static Future<List<FileSystemEntity>> listBackups() async {
    if (kIsWeb) return [];
    try {
      final dir = await getBackupDir();
      await enforceMaxBackupLimit(dir);
      final files = dir.listSync().where((f) {
        final lower = f.path.toLowerCase();
        return lower.endsWith('.db') || lower.endsWith('.mtbk');
      }).toList();
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return files;
    } catch (_) {
      return [];
    }
  }

  /// تجهيز ملف نسخة مشفر مؤقتاً للتصدير أو المشاركة لحماية بيانات المعرض والعملاء
  static Future<File> _prepareExportFile(File sourceFile, {required bool encrypt}) async {
    if (!encrypt) return sourceFile;
    final rawBytes = await sourceFile.readAsBytes();
    final encrypted = BackupCrypto.isEncryptedBytes(rawBytes)
        ? rawBytes
        : BackupCrypto.encryptBytes(rawBytes);

    final tempDir = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempDir.path, 'encrypted_exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final baseName = p.basenameWithoutExtension(sourceFile.path);
    final outFile = File(p.join(exportDir.path, '$baseName.mtbk'));
    await outFile.writeAsBytes(encrypted, flush: true);
    return outFile;
  }

  /// فك تشفير ملف نسخة إن كان مشفراً وإرجاع مسار ملف SQLite جاهز للفحص والاستعادة
  static Future<({String sqlitePath, bool wasTemporary})> _materializePlainSqlite(
    String inputPath, {
    String? passphrase,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    if (!BackupCrypto.isEncryptedBytes(bytes)) {
      return (sqlitePath: inputPath, wasTemporary: false);
    }

    final plain = BackupCrypto.decryptBytes(bytes, passphrase: passphrase);
    final tempDir = await getTemporaryDirectory();
    final tmpFile = File(
      p.join(tempDir.path, 'decrypted_restore_${DateTime.now().millisecondsSinceEpoch}.db'),
    );
    await tmpFile.writeAsBytes(plain, flush: true);
    return (sqlitePath: tmpFile.path, wasTemporary: true);
  }

  /// التحقق من أن الملف المختار هو قاعدة بيانات صالحة لنظام FurniFlow (مشفر .mtbk أو غير مشفر .db)
  static Future<bool> isValidBackupDatabase(String filePath, {String? passphrase}) async {
    String? tempToDelete;
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() < 128) {
        return false;
      }

      final materialized = await _materializePlainSqlite(filePath, passphrase: passphrase);
      if (materialized.wasTemporary) {
        tempToDelete = materialized.sqlitePath;
      }

      final plainFile = File(materialized.sqlitePath);
      if (await plainFile.length() < 1024) return false;

      // 1. فحص ترويسة SQLite الرسمية: "SQLite format 3\0"
      const expectedHeader = [
        0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
        0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
      ];
      final raf = await plainFile.open(mode: FileMode.read);
      try {
        final header = await raf.read(16);
        if (header.length < 16) return false;
        for (int i = 0; i < 16; i++) {
          if (header[i] != expectedHeader[i]) return false;
        }
      } finally {
        await raf.close();
      }

      // 2. التأكد من وجود الجداول الأساسية للتطبيق
      final testDb = await openReadOnlyDatabase(materialized.sqlitePath);
      try {
        final rows = await testDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('orders', 'customers', 'categories')",
        );
        return rows.length == 3;
      } finally {
        await testDb.close();
      }
    } catch (_) {
      return false;
    } finally {
      if (tempToDelete != null) {
        try {
          final f = File(tempToDelete);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// تصدير نسخة احتياطية مشفرة إلى مجلد التنزيلات في الهاتف أو الكمبيوتر
  static Future<String?> exportBackupToDownloads(String backupFilePath) async {
    if (kIsWeb) return null;
    final sourceFile = File(backupFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    final encrypt = await AppSettingsService.isBackupEncryptionEnabled();
    final exportFile = await _prepareExportFile(sourceFile, encrypt: encrypt);
    final fileName = p.basename(exportFile.path);

    try {
      if (Platform.isAndroid) {
        return await _transferChannel.invokeMethod<String>(
          'exportBackupToDownloads',
          {'path': exportFile.path, 'fileName': fileName},
        );
      }

      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final dlDir = Directory(p.join(userProfile, 'Downloads', 'FurniFlowBackups'));
          if (!await dlDir.exists()) {
            await dlDir.create(recursive: true);
          }
          final dest = File(p.join(dlDir.path, fileName));
          await exportFile.copy(dest.path);
          await enforceMaxBackupLimit(dlDir);
          return dest.path;
        }
      }

      return null;
    } finally {
      if (exportFile.path != sourceFile.path) {
        try {
          if (await exportFile.exists()) await exportFile.delete();
        } catch (_) {}
      }
    }
  }

  /// إنشاء نسخة جديدة وتصديرها فوراً إلى مجلد التنزيلات
  static Future<String?> createAndExportBackupToDownloads() async {
    final createdPath = await createBackup(isAuto: false);
    if (createdPath.startsWith('فشل') ||
        createdPath.startsWith('قاعدة') ||
        createdPath.startsWith('النسخ')) {
      throw Exception(createdPath);
    }
    return await exportBackupToDownloads(createdPath);
  }

  /// مشاركة نسخة احتياطية مشفرة خارج التطبيق (أندرويد أو فتح المجلد على ويندوز)
  static Future<void> shareBackupFile(String backupFilePath) async {
    if (kIsWeb) {
      throw UnsupportedError('المشاركة المباشرة غير متاحة على الويب.');
    }
    final sourceFile = File(backupFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    final encrypt = await AppSettingsService.isBackupEncryptionEnabled();
    final exportFile = await _prepareExportFile(sourceFile, encrypt: encrypt);

    if (Platform.isAndroid) {
      final showroomName = AppSettingsService.showroomProfileNotifier.value.displayName;
      await _transferChannel.invokeMethod<void>(
        'shareBackupFile',
        {
          'path': exportFile.path,
          'fileName': p.basename(exportFile.path),
          'subject': 'نسخة احتياطية مشفرة - $showroomName',
        },
      );
      return;
    }

    if (Platform.isWindows) {
      final exportedPath = await exportBackupToDownloads(sourceFile.path);
      if (exportedPath != null) {
        await Process.run('explorer', ['/select,', exportedPath]);
      }
      return;
    }

    throw UnsupportedError('المشاركة المباشرة متاحة على Android و Windows.');
  }

  /// اختيار ملف نسخة احتياطية (.mtbk مشفر أو .db تقليدي) من الهاتف أو ويندوز واستعادته بأمان
  static Future<String?> importAndRestoreExternalBackup({String? passphrase}) async {
    if (kIsWeb) {
      throw UnsupportedError('الاستيراد الخارجي غير متاح على المتصفح.');
    }

    String? pickedPath;
    bool isTempPicked = false;

    if (Platform.isAndroid) {
      pickedPath = await _transferChannel.invokeMethod<String>('pickBackupFile');
      isTempPicked = true;
    } else if (Platform.isWindows) {
      pickedPath = await _pickBackupFileOnWindows();
      isTempPicked = false;
    } else {
      throw UnsupportedError('الاستيراد متاح على Android و Windows.');
    }

    if (pickedPath == null || pickedPath.isEmpty) {
      return null;
    }

    final pickedFile = File(pickedPath);
    try {
      final valid = await isValidBackupDatabase(pickedPath, passphrase: passphrase);
      if (!valid) {
        throw Exception('الملف المختار لا يخص قاعدة بيانات FurniFlow أو أنه تالف.');
      }

      // أخذ نسخة وقائية من البيانات الحالية قبل الاستبدال
      await createBackup(isAuto: false, prefix: 'pre_import_backup');

      final restored = await restoreBackup(pickedPath, passphrase: passphrase);
      if (!restored) {
        throw Exception('تعذر استعادة البيانات من الملف المختار.');
      }

      final backupDir = await getBackupDir();
      final dateStr = intl.DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final ext = p.extension(pickedPath).toLowerCase() == '.mtbk' ? '.mtbk' : '.db';
      final savedCopy = File(p.join(backupDir.path, 'imported_backup_$dateStr$ext'));
      await pickedFile.copy(savedCopy.path);
      await enforceMaxBackupLimit(backupDir);

      return p.basename(savedCopy.path);
    } finally {
      if (isTempPicked) {
        try {
          if (await pickedFile.exists()) await pickedFile.delete();
        } catch (_) {}
      }
    }
  }

  static Future<String?> _pickBackupFileOnWindows() async {
    try {
      const script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dlg = New-Object System.Windows.Forms.OpenFileDialog
\$dlg.Title = "اختر ملف النسخة الاحتياطية (FurniFlow)"
\$dlg.Filter = "FurniFlow Backups (*.mtbk;*.db)|*.mtbk;*.db|All Files (*.*)|*.*"
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

  /// استعادة نسخة احتياطية بأمان (تقبل .mtbk المشفر أو .db التقليدي) مع حماية إعدادات البصمة
  static Future<bool> restoreBackup(String backupFilePath, {String? passphrase}) async {
    if (kIsWeb) return false;
    String? tempPlainPath;
    try {
      final backupFile = File(backupFilePath);
      if (!await backupFile.exists() || await backupFile.length() == 0) {
        return false;
      }

      final materialized = await _materializePlainSqlite(backupFilePath, passphrase: passphrase);
      if (materialized.wasTemporary) {
        tempPlainPath = materialized.sqlitePath;
      }

      // 1. إغلاق اتصال قاعدة البيانات الحالي بأمان لمنع أي أقفال ملفات
      await DBHelper.instance.closeDatabase();

      // 2. نسخ ملف الداتابيز الفعلي
      final destFile = await getDatabaseFile();
      await File(materialized.sqlitePath).copy(destFile.path);

      // 3. إعادة فتح اتصال قاعدة البيانات وتحديث الجداول والفهارس
      final db = await DBHelper.instance.database;
      try {
        await db.execute('PRAGMA optimize');
        await db.execute('VACUUM');
      } catch (_) {}

      // 4. إعادة تحميل هوية المعرض وتحديث الشاشات (مع بقاء البصمة والترخيص محميين في SecurityStorageService)
      await AppSettingsService.loadShowroomProfile();
      AppEvents.instance.notifyAll();
      return true;
    } catch (_) {
      await DBHelper.instance.database;
      return false;
    } finally {
      if (tempPlainPath != null) {
        try {
          final f = File(tempPlainPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// تنظيف الكاش الذكي عند بدء التشغيل دون التسبب في أي بطء لواجهة المستخدم
  static void performSmartStartupMaintenance() {
    Future.microtask(() async {
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          for (var entity in tempDir.listSync(recursive: true)) {
            if (entity is File) {
              try {
                final stat = await entity.stat();
                if (DateTime.now().difference(stat.modified).inHours >= 24) {
                  await entity.delete();
                }
              } catch (_) {}
            }
          }
        }

        PaintingBinding.instance.imageCache.clear();
        await performDailyAutoBackup();
        await CloudService.performDailySilentCloudBackup();

        final db = await DBHelper.instance.database;
        await db.execute('PRAGMA optimize');
      } catch (_) {}
    });
  }

  /// تنظيف الكاش اليدوي وضغط قاعدة البيانات (VACUUM)
  static Future<String> clearAppCache() async {
    int totalDeletedBytes = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (var entity in tempDir.listSync(recursive: true)) {
          if (entity is File) {
            try {
              totalDeletedBytes += await entity.length();
              await entity.delete();
            } catch (_) {}
          }
        }
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      final db = await DBHelper.instance.database;
      await db.execute('PRAGMA optimize');
      await db.execute('VACUUM');
    } catch (_) {}

    final kb = (totalDeletedBytes / 1024).toStringAsFixed(1);
    return 'تم تنظيف الكاش وضغط قاعدة البيانات بالكامل بنجاح ($kb KB)';
  }

  /// -------------------------------------------------------------------------
  /// الأرشفة الذكية (Smart Archiving)
  /// -------------------------------------------------------------------------

  static Future<int> getArchivableOrdersCount(int months) async {
    try {
      final db = await DBHelper.instance.database;
      final threshold = DateTime.now().subtract(Duration(days: months * 30));
      final thresholdStr = intl.DateFormat('yyyy-MM-dd').format(threshold);

      final count = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM orders WHERE status = 'delivered' AND (delivery_date <= ? OR created_at <= ?)",
        [thresholdStr, thresholdStr],
      ));
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> getTotalArchivedOrdersCount() async {
    try {
      final db = await DBHelper.instance.database;
      final count = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM archived_orders"));
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// تنفيذ الأرشفة الذكية مع الحفاظ الكامل على sets_count وtotal_price وpaid_amount
  static Future<int> archiveOrders(int months) async {
    try {
      final db = await DBHelper.instance.database;
      final threshold = DateTime.now().subtract(Duration(days: months * 30));
      final thresholdStr = intl.DateFormat('yyyy-MM-dd').format(threshold);
      final todayStr = intl.DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

      final ordersToArchive = await db.query(
        'orders',
        where: "status = 'delivered' AND (delivery_date <= ? OR created_at <= ?)",
        whereArgs: [thresholdStr, thresholdStr],
      );

      if (ordersToArchive.isEmpty) return 0;

      await createBackup(prefix: 'archive_backup_${months}m');

      final batch = db.batch();
      for (final o in ordersToArchive) {
        batch.insert('archived_orders', {
          'id': o['id'],
          'customer_id': o['customer_id'],
          'customer_name': o['customer_name'],
          'category_id': o['category_id'],
          'category_name': o['category_name'],
          'selected_components_json': o['selected_components_json'],
          'specs': o['specs'],
          'delivery_date': o['delivery_date'],
          'order_type': o['order_type'],
          'sets_count': o['sets_count'] ?? 1,
          'total_price': o['total_price'] ?? 0,
          'paid_amount': o['paid_amount'] ?? 0,
          'status': o['status'],
          'created_at': o['created_at'],
          'archived_at': todayStr,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        batch.delete('orders', where: 'id = ?', whereArgs: [o['id']]);
      }
      await batch.commit(noResult: true);

      await db.execute('PRAGMA optimize');
      await db.execute('VACUUM');

      AppEvents.instance.notifyAll();
      return ordersToArchive.length;
    } catch (_) {
      return -1;
    }
  }

  /// استرجاع كل الطلبات من الأرشيف مع الحفاظ الكامل على sets_count وtotal_price وpaid_amount
  static Future<int> restoreAllArchivedOrders() async {
    try {
      final db = await DBHelper.instance.database;
      final archived = await db.query('archived_orders');
      if (archived.isEmpty) return 0;

      final batch = db.batch();
      for (final a in archived) {
        batch.insert('orders', {
          'customer_id': a['customer_id'],
          'customer_name': a['customer_name'],
          'category_id': a['category_id'],
          'category_name': a['category_name'],
          'selected_components_json': a['selected_components_json'],
          'specs': a['specs'],
          'delivery_date': a['delivery_date'],
          'order_type': a['order_type'],
          'sets_count': a['sets_count'] ?? 1,
          'total_price': a['total_price'] ?? 0,
          'paid_amount': a['paid_amount'] ?? 0,
          'status': 'delivered',
          'created_at': a['created_at'],
        });
      }
      batch.delete('archived_orders');
      await batch.commit(noResult: true);

      await db.execute('VACUUM');
      AppEvents.instance.notifyAll();
      return archived.length;
    } catch (_) {
      return -1;
    }
  }

  /// إعادة ضبط المصنع: تصفير البيانات التشغيلية فقط دون المساس بقفل البصمة أو الترخيص أو النسخ الاحتياطية
  static Future<bool> factoryReset() async {
    try {
      final db = await DBHelper.instance.database;
      await db.transaction((txn) async {
        await txn.delete('orders');
        try { await txn.delete('archived_orders'); } catch (_) {}
        try { await txn.delete('customers'); } catch (_) {}
        try { await txn.delete('categories'); } catch (_) {}
        try { await txn.delete('upholsterer_batches'); } catch (_) {}
        try { await txn.delete('upholsterer_transactions'); } catch (_) {}
        try { await txn.delete('stock_movements'); } catch (_) {}
        // ملاحظة أمنية: لا يتم مسح SecurityStorageService (البصمة والترخيص)، ولا يُمسح ملف النسخ الاحتياطية
      });

      try {
        await db.execute('PRAGMA optimize');
        await db.execute('VACUUM');
      } catch (_) {}

      AppEvents.instance.notifyAll();
      return true;
    } catch (_) {
      return false;
    }
  }
}
