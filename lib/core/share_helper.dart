import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_theme.dart';
import 'pdf_image_document_builder.dart';

enum ShareFormat { image, pdf }

class ShareHelper {
  static const MethodChannel _channel = MethodChannel('com.furniflow.erp/share');

  /// التقاط الويدجت المربوط بـ [boundaryKey] كصورة عالية الدقة (PNG أو بايتات RGBA خام للـ PDF)
  static Future<({Uint8List bytes, int width, int height, bool isRawRgba})?> _captureWidget({
    required GlobalKey boundaryKey,
    required ShareFormat format,
  }) async {
    // ضمان اكتمال إطار الرسم وتجنب استدعاء toImage أثناء إعادة البناء
    await Future.delayed(const Duration(milliseconds: 60));
    if (WidgetsBinding.instance.hasScheduledFrame) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final RenderObject? renderObj = boundaryKey.currentContext?.findRenderObject();
    if (renderObj is! RenderRepaintBoundary) {
      return null;
    }

    if (renderObj.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final Size widgetSize = renderObj.size;
    if (widgetSize.isEmpty || widgetSize.width <= 0 || widgetSize.height <= 0) {
      return null;
    }
    final double maxDim = widgetSize.width > widgetSize.height ? widgetSize.width : widgetSize.height;
    final double pixelRatio = maxDim > 3200
        ? 1.5
        : (maxDim > 2000 ? 2.0 : 2.5);

    final ui.Image image = await renderObj.toImage(pixelRatio: pixelRatio);
    try {
      if (format == ShareFormat.pdf) {
        // لتوليد PDF نأخذ بايتات RGBA الخام لتحويلها بدقة عالية وضغطها بمحرك FlateDecode
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) return null;
        return (
          bytes: byteData.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          isRawRgba: true,
        );
      } else {
        final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return null;
        return (
          bytes: byteData.buffer.asUint8List(),
          width: image.width,
          height: image.height,
          isRawRgba: false,
        );
      }
    } finally {
      image.dispose();
    }
  }

  /// مشاركة كشف الحساب بصيغة صورة أو ملف PDF على واتساب
  static Future<String?> shareStatementToWhatsApp({
    required GlobalKey boundaryKey,
    required String fileNamePrefix,
    required ShareFormat format,
    String? captionText,
  }) async {
    if (kIsWeb) {
      return 'المشاركة غير مدعومة على نسخة المتصفح.';
    }

    final captured = await _captureWidget(boundaryKey: boundaryKey, format: format);
    if (captured == null) {
      return 'تعذر تجهيز كشف الحساب، يرجى المحاولة مرة أخرى.';
    }

    final Directory tempDir = await getTemporaryDirectory();
    final Directory shareDir = Directory(p.join(tempDir.path, 'shared_statements'));
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }

    final String safePrefix = fileNamePrefix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    final String filePath;
    final String mimeType;
    if (format == ShareFormat.pdf) {
      filePath = p.join(shareDir.path, '${safePrefix}_$timestamp.pdf');
      mimeType = 'application/pdf';
      final pdfBytes = PdfImageDocumentBuilder.buildFromRawRgba(
        width: captured.width,
        height: captured.height,
        rgbaBytes: captured.bytes,
      );
      final File file = File(filePath);
      await file.writeAsBytes(pdfBytes, flush: true);
    } else {
      filePath = p.join(shareDir.path, '${safePrefix}_$timestamp.png');
      mimeType = 'image/png';
      final File file = File(filePath);
      await file.writeAsBytes(captured.bytes, flush: true);
    }

    final File shareFile = File(filePath);
    try {
      await _channel.invokeMethod('shareFileToWhatsApp', {
        'path': shareFile.path,
        'text': captionText ?? '',
        'mimeType': mimeType,
      });
      return null;
    } on MissingPluginException {
      return 'تم حفظ الملف في: ${shareFile.path}\n(المشاركة المباشرة متاحة على تطبيق الأندرويد)';
    } on PlatformException catch (e) {
      return e.message ?? 'تعذر فتح تطبيق واتساب للمشاركة.';
    }
  }

  /// التوافق القديم: التقاط الويدجت ومشاركته كصورة
  static Future<String?> captureAndShareToWhatsApp({
    required GlobalKey boundaryKey,
    required String fileNamePrefix,
    String? captionText,
  }) => shareStatementToWhatsApp(
    boundaryKey: boundaryKey,
    fileNamePrefix: fileNamePrefix,
    format: ShareFormat.image,
    captionText: captionText,
  );

  /// عرض نافذة اختيار نوع التصدير (صورة عادية أو ملف PDF) قبل المشاركة
  static Future<ShareFormat?> showExportFormatDialog(BuildContext context) {
    return showModalBottomSheet<ShareFormat>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF128C7E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.share_rounded, color: Color(0xFF128C7E), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مشاركة كشف الحساب عبر واتساب',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(ctx),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر صيغة التصدير المناسبة للمستلم:',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textMuted(ctx),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  tileColor: AppTheme.subtleBg(ctx),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppTheme.borderColor(ctx)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_rounded, color: Colors.blue, size: 24),
                  ),
                  title: const Text(
                    'مشاركة كصورة (PNG)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  subtitle: const Text(
                    'تظهر مباشرة في المحادثة بجودة عالية وسهلة الرؤية',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.pop(ctx, ShareFormat.image),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  tileColor: AppTheme.subtleBg(ctx),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppTheme.borderColor(ctx)),
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 24),
                  ),
                  title: const Text(
                    'مشاركة كمستند (PDF)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                  ),
                  subtitle: const Text(
                    'ملف مستند رسمي قابل للطباعة والحفظ والتوثيق',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => Navigator.pop(ctx, ShareFormat.pdf),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}


