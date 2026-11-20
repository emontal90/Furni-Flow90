import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// مولّد ملفات PDF خفيف ومستقل تماماً بدون أي مكتبات خارجية.
/// يضمن إنشاء مستند PDF قياسي يحوي كشوفات الحساب بجودتها الكاملة 100%
/// في صفحة ملائمة لمقاسها، ومتوافقة تماماً مع جميع برامج قراءة الـ PDF وتطبيق واتساب.
class PdfImageDocumentBuilder {
  /// توليد مستند PDF عالي الدقة من مصفوفة بايتات بكسلات RGBA خام
  /// [width] و [height] هما أبعاد الصورة بالبكسل.
  /// [rgbaBytes] مصفوفة البايتات الخام (4 بايت لكل بكسل: Red, Green, Blue, Alpha).
  static Uint8List buildFromRawRgba({
    required int width,
    required int height,
    required Uint8List rgbaBytes,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Width and height must be positive numbers');
    }

    // 1. تحويل RGBA إلى RGB مع دمج قناة الشفافية Alpha تلقائياً على خلفية بيضاء نقية (255, 255, 255)
    // لضمان عدم ظهور أي سواد أو تشوه في صفحات الـ PDF
    final int pixelCount = width * height;
    final Uint8List rgb = Uint8List(pixelCount * 3);
    int src = 0;
    int dst = 0;

    for (int i = 0; i < pixelCount; i++) {
      final int r = rgbaBytes[src++];
      final int g = rgbaBytes[src++];
      final int b = rgbaBytes[src++];
      final int a = rgbaBytes[src++];

      if (a == 255) {
        rgb[dst++] = r;
        rgb[dst++] = g;
        rgb[dst++] = b;
      } else if (a == 0) {
        // شفاف بالكامل -> أبيض
        rgb[dst++] = 255;
        rgb[dst++] = 255;
        rgb[dst++] = 255;
      } else {
        // دمج الشفافية مع اللون الأبيض
        final double alpha = a / 255.0;
        rgb[dst++] = ((r * alpha) + (255 * (1.0 - alpha))).round().clamp(0, 255);
        rgb[dst++] = ((g * alpha) + (255 * (1.0 - alpha))).round().clamp(0, 255);
        rgb[dst++] = ((b * alpha) + (255 * (1.0 - alpha))).round().clamp(0, 255);
      }
    }

    // 2. ضغط بيانات RGB الخام بصيغة Deflate/zlib القياسية المتوافقة مع مواصفات PDF FlateDecode
    final List<int> compressedRgb = zlib.encode(rgb);

    return _buildPdf(
      width: width,
      height: height,
      streamBytes: compressedRgb,
      filter: '/FlateDecode',
    );
  }

  /// دعم التوافق مع بيانات الصور المشفرة مسبقاً (مثل JPEG DCTDecode)
  static Uint8List buildSingleImagePdf({
    required int width,
    required int height,
    required Uint8List imageBytes,
    required bool isJpeg,
  }) {
    if (isJpeg) {
      return _buildPdf(
        width: width,
        height: height,
        streamBytes: imageBytes,
        filter: '/DCTDecode',
      );
    }

    // إذا كانت بيانات خام أو مسبقة الضغط
    return _buildPdf(
      width: width,
      height: height,
      streamBytes: imageBytes,
      filter: '/FlateDecode',
    );
  }

  static Uint8List _buildPdf({
    required int width,
    required int height,
    required List<int> streamBytes,
    required String filter,
  }) {
    // الأبعاد بوحدة النقطة (Point) المستخدمة في PDF (72 point = 1 inch)
    // نعتمد عرض قياسي 595.28 نقطة (عرض صفحة A4)، ونحسب الارتفاع بما يناسب نسبة الصورة
    const double pageWidth = 595.28;
    final double pageHeight = pageWidth * (height / width);

    final List<List<int>> chunks = [];
    final List<int> offsets = [];

    void addObj(String body) {
      final int currentOffset = chunks.fold(0, (acc, c) => acc + c.length);
      offsets.add(currentOffset);
      final String objStr = '${offsets.length} 0 obj\n$body\nendobj\n';
      chunks.add(latin1.encode(objStr));
    }

    // ترويسة ملف الـ PDF القياسية
    chunks.add(latin1.encode('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n'));

    // 1 0 obj: Catalog
    addObj('<< /Type /Catalog /Pages 2 0 R >>');

    // 2 0 obj: Pages
    addObj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');

    // 3 0 obj: Page
    final String mediaBox = '[0 0 ${pageWidth.toStringAsFixed(2)} ${pageHeight.toStringAsFixed(2)}]';
    addObj(
      '<< /Type /Page /Parent 2 0 R /MediaBox $mediaBox /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>',
    );

    // 4 0 obj: Image XObject
    final int imgOffset = chunks.fold(0, (acc, c) => acc + c.length);
    offsets.add(imgOffset);

    final String imgHeader =
        '4 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter $filter /Length ${streamBytes.length} >>\nstream\n';
    final List<int> imgHeaderBytes = latin1.encode(imgHeader);
    final List<int> imgFooterBytes = latin1.encode('\nendstream\nendobj\n');

    final BytesBuilder imgObjBuilder = BytesBuilder(copy: false);
    imgObjBuilder.add(imgHeaderBytes);
    imgObjBuilder.add(streamBytes);
    imgObjBuilder.add(imgFooterBytes);
    chunks.add(imgObjBuilder.takeBytes());

    // 5 0 obj: Page content stream (رسم الصورة بحجم الصفحة بالكامل)
    final String pageStreamBody =
        'q\n${pageWidth.toStringAsFixed(2)} 0 0 ${pageHeight.toStringAsFixed(2)} 0 0 cm\n/Im1 Do\nQ\n';
    final List<int> pageStreamBytes = latin1.encode(pageStreamBody);
    addObj('<< /Length ${pageStreamBytes.length} >>\nstream\n${pageStreamBody}endstream');

    // xref table
    final int xrefOffset = chunks.fold(0, (acc, c) => acc + c.length);
    final StringBuffer xref = StringBuffer();
    xref.write('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
    for (final off in offsets) {
      xref.write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    xref.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');
    chunks.add(latin1.encode(xref.toString()));

    final BytesBuilder result = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      result.add(chunk);
    }
    return result.takeBytes();
  }
}
