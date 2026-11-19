import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite/sqflite.dart';

/// ملخص موحد لنتائج حساب الأطقم الكاملة والقطع الفردية الزائدة (مصدر الحقيقة الوحيد في النظام)
class StockBreakdown {
  final int completeSets;
  final int individualPieces;
  final int totalPieces;
  final List<Map<String, dynamic>> excessPieces;

  const StockBreakdown({
    required this.completeSets,
    required this.individualPieces,
    required this.totalPieces,
    required this.excessPieces,
  });
}

class CategoryStockHelper {
  static int parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  /// استخراج قائمة المكونات بشكل آمن من JSON أو List
  static List<Map<String, dynamic>> parseComponents(dynamic raw) {
    if (raw == null) return const [];
    try {
      final decoded = raw is List ? raw : jsonDecode(raw.toString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// دالة موحدة لحساب الأطقم الكاملة والقطع الفردية الزائدة وتفاصيلها لأي قائمة قطع
  /// تُستخدم في مخزن المعرض، لوحة التحكم، وشاشة المنجد لمنع تكرار الحسابات
  static StockBreakdown computeBreakdownFromPieces(
    List<Map<String, dynamic>> pieces, {
    String qtyKey = 'qty',
    String? subtractKey,
    int expectedComponentCount = 0,
  }) {
    if (pieces.isEmpty) {
      return const StockBreakdown(
        completeSets: 0,
        individualPieces: 0,
        totalPieces: 0,
        excessPieces: [],
      );
    }

    final List<int> qtys = [];
    final List<int> bases = [];
    final List<String> names = [];
    int totalPieces = 0;

    for (final c in pieces) {
      final rawQ = parseInt(c[qtyKey]);
      final subQ = subtractKey != null ? parseInt(c[subtractKey]) : 0;
      final effectiveQ = math.max(0, rawQ - subQ);
      final rawBase = parseInt(c['base_qty'], fallback: 1);
      final safeBase = rawBase > 0 ? rawBase : 1;

      qtys.add(effectiveQ);
      bases.add(safeBase);
      names.add((c['name'] ?? 'قطعة').toString());
      totalPieces += effectiveQ;
    }

    if (totalPieces <= 0) {
      return const StockBreakdown(
        completeSets: 0,
        individualPieces: 0,
        totalPieces: 0,
        excessPieces: [],
      );
    }

    int completeSets = 0;
    if (expectedComponentCount == 0 || qtys.length >= expectedComponentCount) {
      completeSets = qtys[0] ~/ bases[0];
      for (int i = 1; i < qtys.length; i++) {
        completeSets = math.min(completeSets, qtys[i] ~/ bases[i]);
      }
      if (completeSets < 0) completeSets = 0;
    }

    int individualPieces = 0;
    final excessList = <Map<String, dynamic>>[];
    for (int i = 0; i < qtys.length; i++) {
      final excess = qtys[i] - (completeSets * bases[i]);
      if (excess > 0) {
        individualPieces += excess;
        excessList.add({
          'name': names[i],
          'excess_qty': excess,
          'rem_qty': excess,
          'total_qty': qtys[i],
          'base_qty': bases[i],
        });
      }
    }

    return StockBreakdown(
      completeSets: completeSets,
      individualPieces: individualPieces,
      totalPieces: totalPieces,
      excessPieces: excessList,
    );
  }

  /// استخراج التفصيل الكامل لصنف في المخزن
  static StockBreakdown calculateCategoryBreakdown(Map<String, dynamic> cat) {
    final comps = parseComponents(cat['components_json']);
    if (comps.isNotEmpty) {
      return computeBreakdownFromPieces(comps, qtyKey: 'qty');
    }
    final fallbackSets = math.max(0, parseInt(cat['stock_qty']));
    return StockBreakdown(
      completeSets: fallbackSets,
      individualPieces: 0,
      totalPieces: 0,
      excessPieces: const [],
    );
  }

  /// استخراج عدد الأطقم الكاملة المتوفرة في المخزن لصنف معين بدقة
  static int calculateCompleteSets(Map<String, dynamic> cat) {
    return calculateCategoryBreakdown(cat).completeSets;
  }

  /// استخراج عدد القطع الفردية الزائدة (التي لا تكمل طقماً كاملاً)
  static int calculateIndividualPieces(Map<String, dynamic> cat) {
    return calculateCategoryBreakdown(cat).individualPieces;
  }

  /// صياغة نص موحد يجمع الأطقم والفردي (مثال: "2 طقم و 3 فردي")
  static String formatSetsAndIndividual(int sets, int individual) {
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

  /// نص موجز ومحدد يوضح رصيد المعرض الحقيقي بدقة
  static String formatStockSummary(Map<String, dynamic> cat) {
    final b = calculateCategoryBreakdown(cat);
    return formatSetsAndIndividual(b.completeSets, b.individualPieces);
  }

  /// صياغة عنصر القائمة المنسدلة لاختيار الأصناف
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
