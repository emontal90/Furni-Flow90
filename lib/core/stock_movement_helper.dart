import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart' as intl;
import 'db_helper.dart';

class StockMovementHelper {
  /// تحويل التاريخ والوقت إلى صيغة 12 ساعة بالعربية (ص / م)
  static String formatDateTime12(DateTime dt) {
    final dateStr = intl.DateFormat('yyyy-MM-dd').format(dt);
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'م' : 'ص';
    final hourStr = hour.toString().padLeft(2, '0');
    return '$dateStr $hourStr:$minute $period';
  }

  /// تحويل أي نص تاريخ ووقت قديم من 24 ساعة إلى 12 ساعة
  static String formatDateString12(String raw) {
    if (raw.trim().isEmpty) return '';
    if (raw.contains('ص') || raw.contains('م') || raw.contains('AM') || raw.contains('PM')) {
      return raw;
    }
    try {
      final parts = raw.trim().split(' ');
      if (parts.length >= 2) {
        final dateParts = parts[0].split('-');
        final timeParts = parts[1].split(':');
        if (dateParts.length == 3 && timeParts.length >= 2) {
          final dt = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
          return formatDateTime12(dt);
        }
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return formatDateTime12(parsed);
      }
    } catch (_) {}
    return raw;
  }

  /// تسجيل حركة مخزن جديدة وتوثيق التاريخ والوقت بصيغة 12 ساعة بدقة
  static Future<void> logMovement({
    required int categoryId,
    required String categoryName,
    required String movementType, // 'upholsterer_in', 'delivered_out', 'manual_add', 'manual_deduct', 'upholsterer_out'
    required int qtyChange,
    required int stockAfter,
    required String notes,
  }) async {
    try {
      final db = await DBHelper.instance.database;
      final nowStr = formatDateTime12(DateTime.now());
      await db.insert('stock_movements', {
        'category_id': categoryId,
        'category_name': categoryName,
        'movement_type': movementType,
        'qty_change': qtyChange,
        'stock_after': stockAfter,
        'notes': notes,
        'created_at': nowStr,
      });
    } catch (_) {}
  }

  /// استرجاع كشوفات وتواريخ الحركات لتحديد رصيد المخزن في نهاية تاريخ محدد
  static DateTime? parseMovementDate(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final iso = DateTime.tryParse(raw.trim());
      if (iso != null) return iso;

      final parts = raw.trim().split(' ');
      if (parts.isNotEmpty) {
        final dateParts = parts[0].split('-');
        if (dateParts.length == 3) {
          int y = int.parse(dateParts[0]);
          int m = int.parse(dateParts[1]);
          int d = int.parse(dateParts[2]);
          int h = 0;
          int min = 0;
          if (parts.length >= 2) {
            final timeParts = parts[1].split(':');
            if (timeParts.length >= 2) {
              h = int.tryParse(timeParts[0]) ?? 0;
              min = int.tryParse(timeParts[1]) ?? 0;
            }
            if (parts.length >= 3) {
              final p = parts[2].trim();
              if (p == 'م' || p == 'PM') {
                if (h < 12) h += 12;
              } else if (p == 'ص' || p == 'AM') {
                if (h == 12) h = 0;
              }
            }
          }
          return DateTime(y, m, d, h, min);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// حساب حالة المخزن (الأطقم والقطع) كما كانت بنهاية تاريخ محدد
  static Future<List<Map<String, dynamic>>> getStockAtEndOfDate({
    required List<Map<String, dynamic>> currentCategories,
    required DateTime targetDate,
    List<Map<String, dynamic>>? mockMovements,
  }) async {
    final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);
    final List<Map<String, dynamic>> allMovements;
    if (mockMovements != null) {
      allMovements = mockMovements;
    } else {
      final db = await DBHelper.instance.database;
      allMovements = await db.query(
        'stock_movements',
        orderBy: 'id ASC',
      );
    }

    // جمع الحركات التي حدثت بعد نهاية اليوم المحدد لعكس تأثيرها
    final movementsAfterTarget = <Map<String, dynamic>>[];
    for (final m in allMovements) {
      final String rawDate = (m['created_at'] ?? '').toString();
      final dt = parseMovementDate(rawDate);
      if (dt != null && dt.isAfter(endOfDay)) {
        movementsAfterTarget.add(m);
      }
    }

    // بناء قائمة الأصناف مع عكس الحركات اللاحقة للعودة للوراء
    final result = <Map<String, dynamic>>[];

    for (final cat in currentCategories) {
      final catId = cat['id'] as int;

      List currentComps = [];
      try {
        currentComps = jsonDecode((cat['components_json'] ?? '[]').toString());
      } catch (_) {}

      final Map<String, int> pieceQuantities = {};
      final Map<String, int> pieceBaseQuantities = {};

      for (final c in currentComps) {
        if (c is! Map) continue;
        final name = (c['name'] ?? '').toString().trim();
        final int qty = (c['qty'] is int) ? c['qty'] as int : (int.tryParse('${c['qty']}') ?? 0);
        final int baseQty = (c['base_qty'] is int) ? c['base_qty'] as int : (int.tryParse('${c['base_qty']}') ?? 1);
        if (name.isNotEmpty) {
          pieceQuantities[name] = qty;
          pieceBaseQuantities[name] = baseQty > 0 ? baseQty : 1;
        }
      }

      int catStockSets = (cat['stock_qty'] as int?) ?? 0;

      // عكس الحركات اللاحقة للطقم الحالي من الأحدث إلى الأقدم
      final catMovementsAfter = movementsAfterTarget.where((m) => m['category_id'] == catId).toList();
      // لعكس العمليات التي تمت بعد التاريخ المحدد:
      for (final m in catMovementsAfter) {
        final type = (m['movement_type'] ?? '').toString();
        final int change = (m['qty_change'] as int?) ?? 0;
        final notes = (m['notes'] ?? '').toString();

        if (type == 'upholsterer_in' || type == 'manual_add') {
          catStockSets -= change;
          // تم استلام طقم كامل بقطعه التأسيسية
          if (type == 'upholsterer_in') {
            for (final entry in pieceQuantities.entries) {
              final b = pieceBaseQuantities[entry.key] ?? 1;
              pieceQuantities[entry.key] = math.max(0, entry.value - (change * b));
            }
          }
        } else if (type == 'manual_deduct') {
          catStockSets -= change; // change is negative so subtracting adds back
        } else if (type == 'delivered_out') {
          // تم تسليم طقم أو قطع للعميل -> نعيدها للمخزن
          catStockSets -= change;
          // استخراج تفاصيل القطع المسلمة من الملاحظات إن وجدت مثل [كنبة: 1، فوتيه: 2]
          final exp = RegExp(r'\[(.*?)\]');
          final match = exp.firstMatch(notes);
          if (match != null) {
            final inside = match.group(1) ?? '';
            final parts = inside.split('،');
            for (final part in parts) {
              final sub = part.split(':');
              if (sub.length == 2) {
                final pName = sub[0].trim();
                final pQ = int.tryParse(sub[1].trim()) ?? 0;
                if (pieceQuantities.containsKey(pName)) {
                  pieceQuantities[pName] = pieceQuantities[pName]! + pQ;
                }
              }
            }
          } else {
            // تسليم طقم كامل، نعيد القطع التأسيسية
            final absSets = change.abs() > 0 ? change.abs() : 1;
            for (final entry in pieceQuantities.entries) {
              final b = pieceBaseQuantities[entry.key] ?? 1;
              pieceQuantities[entry.key] = entry.value + (absSets * b);
            }
          }
        } else if (type == 'piece_add') {
          // قطعة مفردة تمت زيادتها أو استلامها -> نعكس بخصمها
          final exp = RegExp(r'قطعة \((.*?)\)');
          final match = exp.firstMatch(notes);
          if (match != null) {
            final pName = match.group(1)?.trim() ?? '';
            if (pieceQuantities.containsKey(pName)) {
              pieceQuantities[pName] = math.max(0, pieceQuantities[pName]! - change);
            }
          }
        } else if (type == 'piece_deduct') {
          // قطعة مفردة تم إنقاصها -> نعكس بزيادتها
          final exp = RegExp(r'قطعة \((.*?)\)');
          final match = exp.firstMatch(notes);
          if (match != null) {
            final pName = match.group(1)?.trim() ?? '';
            if (pieceQuantities.containsKey(pName)) {
              pieceQuantities[pName] = pieceQuantities[pName]! + change.abs();
            }
          }
        }
      }

      final reconstructedComps = pieceQuantities.entries.map((e) {
        return {
          'name': e.key,
          'qty': e.value,
          'base_qty': pieceBaseQuantities[e.key] ?? 1,
        };
      }).toList();

      if (reconstructedComps.isNotEmpty) {
        catStockSets = reconstructedComps.map<int>((c) {
          final q = c['qty'] as int;
          final b = c['base_qty'] as int;
          return q ~/ (b > 0 ? b : 1);
        }).reduce(math.min);
      }
      if (catStockSets < 0) catStockSets = 0;

      result.add({
        ...cat,
        'stock_qty': catStockSets,
        'components_json': jsonEncode(reconstructedComps),
      });
    }

    return result;
  }

  /// جلب كشف حركة طقم معين من الأحدث للأقدم
  static Future<List<Map<String, dynamic>>> getMovementsForCategory(int categoryId) async {
    try {
      final db = await DBHelper.instance.database;
      return await db.query(
        'stock_movements',
        where: 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'id DESC',
      );
    } catch (_) {
      return [];
    }
  }
}
