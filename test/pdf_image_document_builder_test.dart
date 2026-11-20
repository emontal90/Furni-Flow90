import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/pdf_image_document_builder.dart';

void main() {
  group('PdfImageDocumentBuilder', () {
    test('buildFromRawRgba creates valid PDF with correctly compressed RGB stream', () {
      const width = 10;
      const height = 10;
      final rgba = Uint8List(width * height * 4);

      // نصف الصورة أحمر ونصفها أزرق مع بكسل شفاف جزئياً
      for (int i = 0; i < width * height; i++) {
        final idx = i * 4;
        if (i < 50) {
          rgba[idx] = 255; // R
          rgba[idx + 1] = 0; // G
          rgba[idx + 2] = 0; // B
          rgba[idx + 3] = 255; // A (opaque)
        } else if (i == 50) {
          rgba[idx] = 0;
          rgba[idx + 1] = 0;
          rgba[idx + 2] = 255;
          rgba[idx + 3] = 0; // fully transparent -> should blend to pure white (255, 255, 255)
        } else {
          rgba[idx] = 0;
          rgba[idx + 1] = 0;
          rgba[idx + 2] = 255;
          rgba[idx + 3] = 255; // blue
        }
      }

      final pdfBytes = PdfImageDocumentBuilder.buildFromRawRgba(
        width: width,
        height: height,
        rgbaBytes: rgba,
      );

      // التحقق من بنية الـ PDF
      expect(pdfBytes, isNotEmpty);
      final pdfString = latin1.decode(pdfBytes);

      expect(pdfString, startsWith('%PDF-1.4'));
      expect(pdfString, contains('/Type /Catalog'));
      expect(pdfString, contains('/Type /Pages'));
      expect(pdfString, contains('/Type /Page'));
      expect(pdfString, contains('/Type /XObject /Subtype /Image'));
      expect(pdfString, contains('/Width 10 /Height 10 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode'));
      expect(pdfString, contains('/Im1 Do'));
      expect(pdfString, contains('xref'));
      expect(pdfString, contains('trailer'));
      expect(pdfString, contains('startxref'));
      expect(pdfString.trim(), endsWith('%%EOF'));

      // التحقق من أن تيار البيانات المضغوط zlib يمكن فك ضغطه بنجاح ومطابق للبيانات الأصلية
      final streamStart = pdfString.indexOf('stream\n') + 'stream\n'.length;
      final streamEnd = pdfString.indexOf('\nendstream');
      expect(streamStart, greaterThan(0));
      expect(streamEnd, greaterThan(streamStart));

      final compressedBytes = pdfBytes.sublist(streamStart, streamEnd);
      final decompressed = zlib.decode(compressedBytes);

      expect(decompressed.length, equals(width * height * 3));
      // أول بكسل أحمر
      expect(decompressed[0], 255);
      expect(decompressed[1], 0);
      expect(decompressed[2], 0);

      // البكسل رقم 50 كان شفافاً، تم دمجه مع الأبيض -> (255, 255, 255) وليس أسود!
      const idx50 = 50 * 3;
      expect(decompressed[idx50], 255);
      expect(decompressed[idx50 + 1], 255);
      expect(decompressed[idx50 + 2], 255);
    });

    test('buildFromRawRgba throws ArgumentError on non-positive dimensions', () {
      expect(
        () => PdfImageDocumentBuilder.buildFromRawRgba(
          width: 0,
          height: 10,
          rgbaBytes: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });
  });
}
