import 'dart:convert';
import 'dart:typed_data';

/// مولّد ملفات PDF خفيف ومستقل تماماً بدون أي مكتبات خارجية.
/// يضمن إنشاء مستند PDF قياسي يحوي الصورة الأصلية بجودتها الكاملة 100%
/// في صفحة ملائمة لمقاسها، ومتوافقة مع جميع برامج قراءة الـ PDF وتطبيق واتساب.
class PdfImageDocumentBuilder {
  /// توليد مستند PDF من بيانات صورة خام بصيغة JPEG أو PNG
  /// [width] و [height] هما أبعاد الصورة بالبكسل.
  /// [imageBytes] هي مصفوفة بايتات الصورة.
  /// [isJpeg] تحدد ما إذا كانت الصورة بتشفير JPEG (تستخدم DCTDecode مباشرة) أو يتم استخدام FlateDecode للبيانات.
  static Uint8List buildSingleImagePdf({
    required int width,
    required int height,
    required Uint8List imageBytes,
    required bool isJpeg,
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

    final String filter = isJpeg ? '/DCTDecode' : '/FlateDecode';
    final String imgHeader =
        '4 0 obj\n<< /Type /XObject /Subtype /Image /Width $width /Height $height /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter $filter /Length ${imageBytes.length} >>\nstream\n';
    final List<int> imgHeaderBytes = latin1.encode(imgHeader);
    final List<int> imgFooterBytes = latin1.encode('\nendstream\nendobj\n');

    final BytesBuilder imgObjBuilder = BytesBuilder(copy: false);
    imgObjBuilder.add(imgHeaderBytes);
    imgObjBuilder.add(imageBytes);
    imgObjBuilder.add(imgFooterBytes);
    chunks.add(imgObjBuilder.takeBytes());

    // 5 0 obj: Page content stream (رسم الصورة بحجم الصفحة بالكامل)
    final String streamBody =
        'q\n${pageWidth.toStringAsFixed(2)} 0 0 ${pageHeight.toStringAsFixed(2)} 0 0 cm\n/Im1 Do\nQ\n';
    final List<int> streamBytes = latin1.encode(streamBody);
    addObj('<< /Length ${streamBytes.length} >>\nstream\n${streamBody}endstream');

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
