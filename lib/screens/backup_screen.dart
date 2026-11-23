import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;
import '../components/app_logo.dart';
import '../components/stat_card.dart';
import '../core/app_events.dart';
import '../core/app_notification.dart';
import '../core/app_theme.dart';
import '../core/backup_service.dart';
import '../core/cloud_service.dart';
import '../core/security_storage_service.dart';
import 'subscription_screen.dart';

class BackupScreen extends StatefulWidget {
  final bool embedded;
  const BackupScreen({super.key, this.embedded = false});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<FileSystemEntity> _backups = [];
  String _dbSize = '0 KB';
  int _archivedOrdersCount = 0;
  bool _isLoading = false;

  // فترة الأرشفة المختارة (بالشهور)
  int _selectedArchiveMonths = 6;
  int _eligibleForArchiveCount = 0;

  // حالة النسخ الاحتياطي السحابي
  List<CloudBackupItem> _cloudBackups = [];
  bool _isCloudLoading = false;
  bool _isUploadingCloud = false;
  bool _isCloudSubscribed = false;
  String _deviceCode = '';

  @override
  void initState() {
    super.initState();
    _loadAllInfo();
    AppEvents.instance.refreshNotifier.addListener(_loadAllInfo);
  }

  @override
  void dispose() {
    AppEvents.instance.refreshNotifier.removeListener(_loadAllInfo);
    super.dispose();
  }

  Future<void> _loadAllInfo() async {
    setState(() => _isLoading = true);
    final backups = await BackupService.listBackups();
    final dbSize = await BackupService.getDatabaseSize();
    final archivedCount = await BackupService.getTotalArchivedOrdersCount();
    final eligible = await BackupService.getArchivableOrdersCount(_selectedArchiveMonths);

    if (mounted) {
      setState(() {
        _backups = backups;
        _dbSize = dbSize;
        _archivedOrdersCount = archivedCount;
        _eligibleForArchiveCount = eligible;
        _isLoading = false;
      });
    }
    _loadCloudInfo();
  }

  Future<void> _loadCloudInfo() async {
    if (kIsWeb) return;
    setState(() => _isCloudLoading = true);
    final code = await SecurityStorageService.getDeviceCode();
    final eligible = await CloudService.isUserEligibleForCloudBackup();
    List<CloudBackupItem> cloudItems = [];
    if (eligible) {
      cloudItems = await CloudService.fetchCloudBackups(code);
    }
    if (mounted) {
      setState(() {
        _deviceCode = code;
        _isCloudSubscribed = eligible;
        _cloudBackups = cloudItems;
        _isCloudLoading = false;
      });
    }
  }

  Future<void> _uploadManualCloudBackup() async {
    if (!_isCloudSubscribed) {
      final sub = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => SubscriptionScreen(deviceCode: _deviceCode),
        ),
      );
      if (sub == true) {
        await _loadCloudInfo();
      }
      return;
    }

    setState(() => _isUploadingCloud = true);
    final res = await CloudService.uploadEncryptedBackup(isAuto: false);
    if (mounted) {
      setState(() => _isUploadingCloud = false);
      if (res.success) {
        AppNotification.showSuccess(context, res.message);
        await _loadCloudInfo();
      } else {
        AppNotification.showError(context, res.message);
      }
    }
  }

  Future<void> _confirmAndRestoreCloud(CloudBackupItem item) async {
    final dateStr = intl.DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt.toLocal());
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_download_rounded, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Text('تأكيد الاستعادة من السحابة', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'تنبيه هام:\nاستعادة هذه النسخة السحابية المشفرة سيستبدل بيانات التطبيق الحالية بالبيانات المحفوظة سحابياً بتاريخ ($dateStr).\n\nحجم النسخة: ${item.fileSizeFormatted}\nاسم الملف: ${item.fileName}\n\nهل ترغب في المتابعة والاستعادة الآن؟',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('نعم، استعادة من السحابة'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final res = await CloudService.restoreFromCloud(item);
      await _loadAllInfo();
      if (mounted) {
        setState(() => _isLoading = false);
        if (res.success) {
          AppNotification.showSuccess(context, res.message);
        } else {
          AppNotification.showError(context, res.message);
        }
      }
    }
  }

  Future<void> _confirmAndDeleteCloud(CloudBackupItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text('حذف نسخة سحابية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف النسخة السحابية (${item.fileName}) نهائياً؟',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('حذف الآن'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await CloudService.deleteCloudBackup(item);
      if (mounted) {
        if (ok) {
          AppNotification.showSuccess(context, 'تم حذف النسخة من السحابة');
          await _loadCloudInfo();
        } else {
          AppNotification.showError(context, 'تعذر حذف النسخة من السحابة');
        }
      }
    }
  }

  Future<void> _updateEligibleCount(int months) async {
    setState(() => _selectedArchiveMonths = months);
    final count = await BackupService.getArchivableOrdersCount(months);
    if (mounted) {
      setState(() => _eligibleForArchiveCount = count);
    }
  }

  // 1. إنشاء نسخة احتياطية يدوية
  Future<void> _createManualBackup() async {
    setState(() => _isLoading = true);
    final res = await BackupService.createBackup(isAuto: false);
    await _loadAllInfo();
    if (mounted) {
      if (res.startsWith('فشل')) {
        AppNotification.showError(context, res);
      } else {
        AppNotification.showSuccess(context, 'تم إنشاء النسخة الاحتياطية اليدوية وضغط البيانات بنجاح');
      }
    }
  }

  // 2. تنظيف الكاش وضغط قاعدة البيانات
  Future<void> _cleanCacheAndVacuum() async {
    setState(() => _isLoading = true);
    final msg = await BackupService.clearAppCache();
    await _loadAllInfo();
    if (mounted) {
      AppNotification.showSuccess(context, msg);
    }
  }

  // 3. تأكيد وتنفيذ الاستعادة
  Future<void> _confirmAndRestore(FileSystemEntity file) async {
    final fileName = p.basename(file.path);
    final date = file.statSync().modified;
    final dateStr = intl.DateFormat('yyyy-MM-dd HH:mm').format(date);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('تأكيد استعادة النسخة الاحتياطية', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'تحذير هام:\nاستعادة هذه النسخة سيستبدل جميع البيانات الحالية للبرنامج بالبيانات المحفوظة في هذه النسخة بتاريخ ($dateStr).\n\nاسم الملف: $fileName\n\nهل أنت متأكد من رغبتك في المتابعة؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('نعم، استعادة الآن'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final ok = await BackupService.restoreBackup(file.path);
      await _loadAllInfo();
      if (mounted) {
        if (ok) {
          AppNotification.showSuccess(context, 'تمت استعادة البيانات بنجاح وتحديث كافة الشاشات');
        } else {
          AppNotification.showError(context, 'فشلت الاستعادة، يرجى التأكد من صلاحيات الملف');
        }
      }
    }
  }

  // 4. حذف نسخة احتياطية قديمة
  Future<void> _deleteBackup(FileSystemEntity file) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text('تأكيد حذف النسخة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف النسخة الاحتياطية "${p.basename(file.path)}" من الذاكرة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('حذف النسخة'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await file.delete();
        await _loadAllInfo();
        if (mounted) {
          AppNotification.showError(context, 'تم حذف ملف النسخة الاحتياطية بنجاح');
        }
      } catch (_) {}
    }
  }

  // 4.1 إنشاء وتصدير نسخة احتياطية إلى مجلد التنزيلات في الهاتف
  Future<void> _createAndExportToDownloads() async {
    setState(() => _isLoading = true);
    try {
      final savedLocation = await BackupService.createAndExportBackupToDownloads();
      await _loadAllInfo();
      if (mounted) {
        if (savedLocation != null && savedLocation.isNotEmpty) {
          AppNotification.showSuccess(
            context,
            'تم حفظ النسخة الاحتياطية في الهاتف:\n$savedLocation',
          );
        } else {
          AppNotification.showInfo(context, 'تم إلغاء حفظ النسخة الخارجية.');
        }
      }
    } catch (e) {
      await _loadAllInfo();
      if (mounted) {
        AppNotification.showError(
          context,
          'تعذر تصدير النسخة: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  // 4.2 تصدير نسخة محددة إلى مجلد التنزيلات
  Future<void> _exportBackupToDownloads(FileSystemEntity file) async {
    try {
      final savedLocation = await BackupService.exportBackupToDownloads(file.path);
      if (mounted) {
        if (savedLocation != null && savedLocation.isNotEmpty) {
          AppNotification.showSuccess(
            context,
            'تم حفظ النسخة في الهاتف:\n$savedLocation',
          );
        } else {
          AppNotification.showInfo(context, 'تم إلغاء عملية الحفظ.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'فشل التصدير: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  // 4.3 مشاركة نسخة احتياطية عبر التطبيقات (واتساب / تيليجرام / Drive)
  Future<void> _shareBackup(FileSystemEntity file) async {
    try {
      await BackupService.shareBackupFile(file.path);
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'تعذر مشاركة النسخة: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
  }

  // 4.4 استيراد نسخة احتياطية (.db) من ذاكرة الهاتف
  Future<void> _importExternalBackup() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.file_upload_outlined, color: AppTheme.primaryNavy, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'استيراد نسخة احتياطية من الهاتف',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'اختر ملف نسخة احتياطية مشفر (.mtbk) أو تقليدي (.db) من ذاكرة الجهاز أو Google Drive.\n\nسيقوم التطبيق أولاً بالتحقق من سلامة الملف وأخذ نسخة وقائية من بياناتك الحالية قبل الاستعادة.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.royalGold,
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('اختيار الملف (.mtbk / .db)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final restoredName = await BackupService.importAndRestoreExternalBackup();
      await _loadAllInfo();
      if (mounted) {
        if (restoredName == null) {
          AppNotification.showInfo(context, 'لم يتم اختيار أي ملف.');
        } else {
          AppNotification.showSuccess(
            context,
            'تم استيراد واستعادة البيانات بنجاح ($restoredName)',
          );
        }
      }
    } catch (e) {
      await _loadAllInfo();
      if (mounted) {
        AppNotification.showError(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }

  // 5. الأرشفة الذكية لفترة معينة
  Future<void> _performSmartArchive() async {
    if (_eligibleForArchiveCount <= 0) {
      AppNotification.showInfo(
        context,
        'لا توجد طلبات مسلّمة أقدم من $_selectedArchiveMonths شهر لأرشفتها.',
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.archive_outlined, color: AppTheme.primaryNavy, size: 28),
            SizedBox(width: 8),
            Text('تأكيد الأرشفة الذكية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'سيتم الآن أرشفة عدد ($_eligibleForArchiveCount) أوردر تم تسليمهم قديماً (أقدم من $_selectedArchiveMonths شهر).\n\n'
          'مميزات العملية:\n'
          '✓ يتم أخذ نسخة احتياطية كاملة وتلقائية قبل البدء.\n'
          '✓ يتم نقل الطلبات القديمة لسجل الأرشيف وحفظها للأبد.\n'
          '✓ يتم ضغط قاعدة البيانات لتسريع التصفح وتوفير المساحة.\n'
          '✓ لن يتم المساس برصيد المخزن أو بطلبات قائمة الانتظار نهائياً.\n\n'
          'هل تريد بدء عملية الأرشفة الآن؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryNavy,
              foregroundColor: AppTheme.royalGold,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('بدء الأرشفة وضغط البيانات'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final count = await BackupService.archiveOrders(_selectedArchiveMonths);
      await _loadAllInfo();
      if (mounted) {
        if (count > 0) {
          AppNotification.showSuccess(
            context,
            'تمت أرشفة $count أوردر بنجاح وإنشاء نسخة احتياطية وقائية وضغط الداتابيز!',
          );
        } else {
          AppNotification.showError(context, 'حدث خطأ أثناء تنفيذ عملية الأرشفة');
        }
      }
    }
  }

  // 6. استرجاع كل الطلبات من الأرشيف
  Future<void> _restoreArchivedOrders() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.unarchive, color: Colors.blue, size: 28),
            SizedBox(width: 8),
            Text('استرجاع الأوردرات المؤرشفة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل تريد إعادة جميع الطلبات المؤرشفة ($_archivedOrdersCount أوردر) إلى قائمة الطلبات المسلّمة النشطة في البرنامج؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('تأكيد الاسترجاع'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      final count = await BackupService.restoreAllArchivedOrders();
      await _loadAllInfo();
      if (mounted) {
        AppNotification.showSuccess(context, 'تمت استعادة $count أوردر من الأرشيف إلى قائمة المسلّم');
      }
    }
  }

  // 7. إعادة ضبط المصنع مع رسالتي تأكيد متتاليتين
  Future<void> _confirmFactoryReset() async {
    // رسالة التأكيد الأولى
    final bool? firstConfirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('إعادة ضبط المصنع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: const Text(
          'تحذير هام!\n\n'
          'هل أنت متأكد من رغبتك في إعادة ضبط المصنع وتصفير كافة بيانات البرنامج؟\n\n'
          '✓ سيتم تصفير جميع الطلبات، العملاء، الأصناف، المخزن، ودفعات المنجد.\n'
          '✓ سيتم الإبقاء على ملفات النسخ الاحتياطية المحفوظة دون أي مساس لتتمكن من استعادتها لاحقاً إذا رغبت.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !mounted) return;

    // رسالة التأكيد الثانية والأخيرة
    final bool? secondConfirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('تأكيد نهائي وحاسم', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          ],
        ),
        content: const Text(
          'هل أنت متأكد تماماً من هذه الخطوة؟\n\n'
          'سيتم الآن حذف وتصفير جميع بيانات البرنامج الحالية نهائياً.\n\n'
          'اضغط على (تأكيد تصفير البيانات) للمتابعة.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('تراجع', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('تأكيد تصفير البيانات'),
          ),
        ],
      ),
    );

    if (secondConfirm == true && mounted) {
      setState(() => _isLoading = true);
      final success = await BackupService.factoryReset();
      await _loadAllInfo();
      if (mounted) {
        if (success) {
          AppNotification.showSuccess(
            context,
            'تمت إعادة ضبط المصنع وتصفير بيانات البرنامج بنجاح، مع بقاء نسخك الاحتياطية محفوظة بأمان.',
          );
        } else {
          AppNotification.showError(context, 'حدث خطأ أثناء محاولة تصفير البيانات.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget bodyContent = SafeArea(
      top: false,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllInfo,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
              children: [
                // 1. بطاقات الإحصائيات والمعلومات السريعة
                Row(
                  children: [
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.data_usage_rounded,
                        title: 'حجم قاعدة البيانات',
                        value: _dbSize,
                        color: Colors.blue.shade700,
                        subtitle: 'مضغوطة وخفيفة',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.backup_rounded,
                        title: 'النسخ الاحتياطية',
                        value: '${_backups.length} / ${BackupService.maxBackups}',
                        color: AppTheme.primaryNavy,
                        subtitle: 'حد أقصى ${BackupService.maxBackups} نسخ تلقائياً',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CompactStatCard(
                        icon: Icons.inventory_2_outlined,
                        title: 'الطلبات بالأرشيف',
                        value: '$_archivedOrdersCount أوردر',
                        color: Colors.brown.shade600,
                        subtitle: 'محفوظة بأمان',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. أزرار الإجراءات السريعة
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryNavy,
                          foregroundColor: AppTheme.royalGold,
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _createManualBackup,
                        icon: const Icon(Icons.add_to_photos_rounded, size: 19),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'إنشاء نسخة احتياطية',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryNavy,
                          side: const BorderSide(color: AppTheme.primaryNavy),
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _cleanCacheAndVacuum,
                        icon: const Icon(Icons.rocket_launch_rounded, size: 19),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'تنظيف الكاش',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal.shade800,
                            side: BorderSide(color: Colors.teal.shade600),
                            backgroundColor: Colors.teal.withValues(alpha: 0.05),
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _createAndExportToDownloads,
                          icon: const Icon(Icons.download_for_offline_rounded, size: 19),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'حفظ نسخة احتياطية',
                              maxLines: 1,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo.shade800,
                            side: BorderSide(color: Colors.indigo.shade500),
                            backgroundColor: Colors.indigo.withValues(alpha: 0.05),
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: (Platform.isAndroid || Platform.isWindows) ? _importExternalBackup : null,
                          icon: const Icon(Icons.file_upload_rounded, size: 19),
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'استيراد نسخة من الهاتف',
                              maxLines: 1,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),

                // 3. قسم الأرشفة الذكية
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppTheme.royalGold.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.auto_fix_high_rounded, color: AppTheme.primaryNavy, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'الأرشفة الذكية للطلبات القديمة',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تتيح لك الأرشفة الذكية نقل الطلبات التي تم تسليمها قديماً إلى سجل الأرشيف لتسريع التطبيق وتوفير المساحة لشغل سنوات قادمة، مع حفظ نسخة احتياطية تلقائياً قبل البدء.',
                          style: TextStyle(color: AppTheme.textMuted(context), fontSize: 13),
                        ),
                        const SizedBox(height: 14),

                        // اختيار فترة الأرشفة
                        const Text(
                          'اختر فترة الأرشفة للطلبات المسلّمة:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _PeriodOptionChip(
                              label: 'أقدم من 3 شهور',
                              months: 3,
                              isSelected: _selectedArchiveMonths == 3,
                              onSelected: () => _updateEligibleCount(3),
                            ),
                            _PeriodOptionChip(
                              label: 'أقدم من 6 شهور',
                              months: 6,
                              isSelected: _selectedArchiveMonths == 6,
                              onSelected: () => _updateEligibleCount(6),
                            ),
                            _PeriodOptionChip(
                              label: 'أقدم من 9 شهور',
                              months: 9,
                              isSelected: _selectedArchiveMonths == 9,
                              onSelected: () => _updateEligibleCount(9),
                            ),
                            _PeriodOptionChip(
                              label: 'أقدم من 12 شهر (سنة)',
                              months: 12,
                              isSelected: _selectedArchiveMonths == 12,
                              onSelected: () => _updateEligibleCount(12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // حالة الطلبات المؤهلة
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _eligibleForArchiveCount > 0 ? Colors.amber.shade50 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _eligibleForArchiveCount > 0 ? Colors.amber.shade300 : Colors.green.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _eligibleForArchiveCount > 0 ? Icons.info_outline : Icons.check_circle_outline,
                                color: _eligibleForArchiveCount > 0 ? Colors.brown : Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _eligibleForArchiveCount > 0
                                      ? 'يوجد حالياً ($_eligibleForArchiveCount) أوردر مسلّم أقدم من $_selectedArchiveMonths شهر مؤهل للأرشفة.'
                                      : 'لا توجد أوردرات مسلّمة أقدم من $_selectedArchiveMonths شهر حالياً.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _eligibleForArchiveCount > 0 ? Colors.brown : Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // زر تنفيذ الأرشفة
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryNavy,
                                  foregroundColor: AppTheme.royalGold,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _eligibleForArchiveCount > 0 ? _performSmartArchive : null,
                                icon: const Icon(Icons.archive_rounded),
                                label: Text(
                                  'أرشفة ($_eligibleForArchiveCount) أوردر الآن',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ),
                            if (_archivedOrdersCount > 0) ...[
                              const SizedBox(width: 8),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue.shade800,
                                ),
                                onPressed: _restoreArchivedOrders,
                                icon: const Icon(Icons.unarchive_rounded, size: 18),
                                label: const Text('استرجاع الأرشيف', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // قسم النسخ الاحتياطي السحابي (سوبا بيز)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _isCloudSubscribed
                          ? Colors.teal.withValues(alpha: 0.5)
                          : AppTheme.royalGold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_done_rounded,
                              color: _isCloudSubscribed ? Colors.teal : AppTheme.royalGold,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'النسخ الاحتياطي السحابي المشفر',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isCloudSubscribed
                                    ? Colors.teal.withValues(alpha: 0.15)
                                    : Colors.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _isCloudSubscribed
                                    ? 'مساحة نشطة (${_cloudBackups.length}/5)'
                                    : 'يتطلب اشتراك',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isCloudSubscribed ? Colors.teal.shade800 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'يتم حفظ نسخة احتياطية يومية مشفرة وصامتة على السحابة بحد أقصى 5 ملفات (حذف التلقائي للأقدم عند التجاوز). ويمكنك أيضاً رفع واستعادة النسخ يدوياً في أي وقت.',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context), height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isCloudSubscribed ? Colors.teal.shade700 : AppTheme.primaryNavy,
                                  foregroundColor: _isCloudSubscribed ? Colors.white : AppTheme.royalGold,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _isUploadingCloud ? null : _uploadManualCloudBackup,
                                icon: _isUploadingCloud
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Icon(_isCloudSubscribed ? Icons.cloud_upload_rounded : Icons.star_rounded, size: 20),
                                label: Text(
                                  _isUploadingCloud
                                      ? 'جاري الرفع والتشفير...'
                                      : _isCloudSubscribed
                                          ? 'رفع نسخة سحابية مشفرة الآن'
                                          : 'اشترك لتفعيل النسخ السحابي',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ),
                            ),
                            if (_isCloudSubscribed) ...[
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                tooltip: 'تحديث النسخ السحابية',
                                onPressed: _isCloudLoading ? null : _loadCloudInfo,
                                icon: _isCloudLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh, size: 18),
                              ),
                            ],
                          ],
                        ),
                        if (_isCloudSubscribed) ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Text(
                            'النسخ المتوفرة على السحابة لهذا الجهاز:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_cloudBackups.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text(
                                  'لا توجد نسخ سحابية محفوظة بعد. اضغط على الزر بالأعلى لرفع أول نسخة.',
                                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context)),
                                ),
                              ),
                            )
                          else
                            ..._cloudBackups.map((cb) {
                              final dt = cb.createdAt.toLocal();
                              final dtStr = intl.DateFormat('yyyy-MM-dd hh:mm a').format(dt);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.subtleBg(context),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.borderColor(context)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      cb.isAuto ? Icons.auto_awesome_rounded : Icons.backup_rounded,
                                      size: 20,
                                      color: cb.isAuto ? Colors.indigo : Colors.teal,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  cb.fileName,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppTheme.textPrimary(context),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: cb.isAuto ? Colors.indigo.withValues(alpha: 0.12) : Colors.teal.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  cb.isAuto ? 'تلقائي' : 'يدوي',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: cb.isAuto ? Colors.indigo : Colors.teal,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$dtStr • ${cb.fileSizeFormatted} (مشفر AES-256)',
                                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.blue.shade700,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      ),
                                      onPressed: () => _confirmAndRestoreCloud(cb),
                                      icon: const Icon(Icons.settings_backup_restore_rounded, size: 16),
                                      label: const Text('استعادة', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف من السحابة',
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                      onPressed: () => _confirmAndDeleteCloud(cb),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 4. قائمة النسخ الاحتياطية المتوفرة
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.folder_shared_rounded, color: AppTheme.primaryNavy, size: 22),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'سجل النسخ الاحتياطية على الموبايل والكمبيوتر',
                              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: AppTheme.primaryNavy),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'تحديث القائمة',
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: _loadAllInfo,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (kIsWeb)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ملاحظة: في بيئة المتصفح (Web)، يتم تخزين قاعدة البيانات والنسخ محلياً في IndexedDB بشكل تلقائي.',
                      style: TextStyle(color: AppTheme.primaryNavy),
                    ),
                  )
                else if (_backups.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Center(
                      child: Text(
                        'لا توجد نسخ احتياطية مسجلة بعد.\nاضغط على (إنشاء نسخة احتياطية الآن) بالأعلى لحفظ أول نسخة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ..._backups.map((file) {
                    final name = p.basename(file.path);
                    final stat = file.statSync();
                    final date = stat.modified;
                    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
                    final isAuto = name.startsWith('auto_backup_');
                    final isArchive = name.startsWith('archive_backup_');
                    final isImported = name.startsWith('imported_backup_');

                    String tag = 'نسخة يدوية';
                    Color tagColor = AppTheme.primaryNavy;
                    Color tagBg = Colors.blue.shade50;

                    if (isAuto) {
                      tag = 'نسخة يومية تلقائية';
                      tagColor = Colors.green.shade800;
                      tagBg = Colors.green.shade50;
                    } else if (isArchive) {
                      tag = 'نسخة أرشيف وقائية';
                      tagColor = Colors.brown.shade800;
                      tagBg = Colors.amber.shade50;
                    } else if (isImported) {
                      tag = 'نسخة مستوردة';
                      tagColor = Colors.indigo.shade800;
                      tagBg = Colors.indigo.shade50;
                    }

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: tagBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                isAuto
                                    ? Icons.schedule_rounded
                                    : (isArchive ? Icons.archive : Icons.save_rounded),
                                color: tagColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: tagBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: tagColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$sizeKb KB',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '📅 ${intl.DateFormat('yyyy-MM-dd HH:mm').format(date)}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'خيارات النسخة',
                              icon: const Icon(Icons.more_vert_rounded, color: AppTheme.primaryNavy),
                              onSelected: (action) {
                                if (action == 'download') {
                                  _exportBackupToDownloads(file);
                                } else if (action == 'share') {
                                  _shareBackup(file);
                                } else if (action == 'delete') {
                                  _deleteBackup(file);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem<String>(
                                  value: 'download',
                                  child: Row(
                                    children: [
                                      Icon(Icons.download_rounded, color: Colors.teal, size: 20),
                                      SizedBox(width: 8),
                                      Text('حفظ في مجلد التنزيلات'),
                                    ],
                                  ),
                                ),
                                if (Platform.isAndroid || Platform.isWindows)
                                  const PopupMenuItem<String>(
                                    value: 'share',
                                    child: Row(
                                      children: [
                                        Icon(Icons.share_rounded, color: AppTheme.primaryNavy, size: 20),
                                        SizedBox(width: 8),
                                        Text('مشاركة (واتساب / درايف)'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      SizedBox(width: 8),
                                      Text('حذف هذه النسخة', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryNavy,
                                foregroundColor: AppTheme.royalGold,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onPressed: () => _confirmAndRestore(file),
                              icon: const Icon(Icons.restore_rounded, size: 16),
                              label: const Text('استعادة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 20),

                // 5. قسم إعادة ضبط المصنع
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.red.shade300, width: 1.2),
                  ),
                  color: Colors.red.shade50.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'إعادة ضبط المصنع',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'تصفير وتفريغ جميع بيانات البرنامج (الزبائن، الأصناف، المخزن، الطلبات، ودفعات المنجد)، مع الإبقاء على ملفات النسخ الاحتياطية المحفوظة دون أي مساس لتتمكن من استعادتها في أي وقت.',
                          style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.45),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _confirmFactoryReset,
                          icon: const Icon(Icons.restore_page_outlined, size: 20),
                          label: const Text(
                            'إعادة ضبط المصنع وتصفير البيانات',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
            ),
    );

    if (widget.embedded) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleWithLogo(title: 'النسخ الاحتياطي والأرشفة الذكية'),
      ),
      body: bodyContent,
    );
  }
}

/// زر اختيار فترة الأرشفة
class _PeriodOptionChip extends StatelessWidget {
  final String label;
  final int months;
  final bool isSelected;
  final VoidCallback onSelected;

  const _PeriodOptionChip({
    required this.label,
    required this.months,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primaryNavy,
      labelStyle: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: isSelected ? AppTheme.royalGold : Colors.black87,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}
