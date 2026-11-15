import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';

class CategoryStockHelper {
  /// استخراج عدد الأطقم الكاملة المتوفرة في المخزن لصنف معين بدقة
  static int calculateCompleteSets(Map<String, dynamic> cat) {
    List comps = [];
    try {
      final raw = cat['components_json'];
      if (raw is List) {
        comps = raw;
      } else if (raw != null && raw.toString().trim().isNotEmpty) {
        final decoded = jsonDecode(raw.toString());
        if (decoded is List) comps = decoded;
      }
    } catch (_) {}

    if (comps.isNotEmpty) {
      final calculated = comps.map<int>((c) {
        if (c is! Map) return 0;
        final q = (c['qty'] is int)
            ? c['qty'] as int
            : (int.tryParse(c['qty']?.toString() ?? '0') ?? 0);
        final b = (c['base_qty'] is int)
            ? c['base_qty'] as int
            : (int.tryParse(c['base_qty']?.toString() ?? '1') ?? 1);
        final safeB = b > 0 ? b : 1;
        return q ~/ safeB;
      }).reduce(math.min);
      return calculated >= 0 ? calculated : 0;
    }

    final rawStock = cat['stock_qty'];
    if (rawStock is int) return rawStock >= 0 ? rawStock : 0;
    final parsed = int.tryParse(rawStock?.toString() ?? '0') ?? 0;
    return parsed >= 0 ? parsed : 0;
  }

  /// استخراج عدد القطع الفردية الزائدة (التي لا تكمل طقماً كاملاً)
  static int calculateIndividualPieces(Map<String, dynamic> cat) {
    List comps = [];
    try {
      final raw = cat['components_json'];
      if (raw is List) {
        comps = raw;
      } else if (raw != null && raw.toString().trim().isNotEmpty) {
        final decoded = jsonDecode(raw.toString());
        if (decoded is List) comps = decoded;
      }
    } catch (_) {}

    if (comps.isEmpty) return 0;

    final completeSets = calculateCompleteSets(cat);
    int excessCount = 0;
    for (final c in comps) {
      if (c is! Map) continue;
      final q = (c['qty'] is int)
          ? c['qty'] as int
          : (int.tryParse(c['qty']?.toString() ?? '0') ?? 0);
      final b = (c['base_qty'] is int)
          ? c['base_qty'] as int
          : (int.tryParse(c['base_qty']?.toString() ?? '1') ?? 1);
      final safeB = b > 0 ? b : 1;
      final excess = q - (completeSets * safeB);
      if (excess > 0) {
        excessCount += excess;
      }
    }
    return excessCount;
  }

  /// نص موجز ومحدد يوضح رصيد المعرض الحقيقي بدقة
  /// مثال: "2 طقم" أو "2 طقم و 3 فردي" أو "4 فردي" أو "0 طقم"
  static String formatStockSummary(Map<String, dynamic> cat) {
    final sets = calculateCompleteSets(cat);
    final individual = calculateIndividualPieces(cat);

    if (sets > 0 && individual > 0) {
      return '$sets طقم و $individual فردي';
    } else if (sets > 0) {
      return '$sets طقم';
    } else if (individual > 0) {
      return '$individual فردي';
    } else {
      return '0 طقم';
    }
  }

  /// صياغة عنصر القائمة المنسدلة لاختيار الأصناف
  /// مثال: "طقم كابوتكا (رصيد المعرض: 2 طقم و 1 فردي)"
  static String formatDropdownItem(Map<String, dynamic> cat, {String prefix = 'رصيد المعرض'}) {
    final name = (cat['name'] ?? '').toString();
    final summary = formatStockSummary(cat);
    return '$name ($prefix: $summary)';
  }

  /// مزامنة حقل stock_qty في قاعدة البيانات لجميع الأصناف ليتطابق دائماً مع الأطقم الكاملة
  static Future<void> syncDatabaseStock(Database db) async {
    try {
      final cats = await db.query('categories');
      for (final cat in cats) {
        final realSets = calculateCompleteSets(cat);
        final currentStockQty = (cat['stock_qty'] as int?) ?? -1;
        if (realSets != currentStockQty) {
          await db.update(
            'categories',
            {'stock_qty': realSets},
            where: 'id = ?',
            whereArgs: [cat['id']],
          );
        }
      }
    } catch (_) {}
  }
}

