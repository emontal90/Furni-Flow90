import 'dart:convert';
import 'dart:math' as math;
import 'package:intl/intl.dart' as intl;
import 'category_stock_helper.dart';
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

  /// تسجيل حركة مخزن جديدة مع تخزين تفاصيل تغير القطع بشكل مهيكل (pieces_json)
  /// بدلاً من الاعتماد الهش على Regex النصوص العربية عند حساب المخزون التاريخي
  static Future<void> logMovement({
    required int categoryId,
    required String categoryName,
    required String movementType,
    required int qtyChange,
    required int stockAfter,
    required String notes,
    List<Map<String, dynamic>>? piecesDelta,
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
        'pieces_json': (piecesDelta != null && piecesDelta.isNotEmpty)
            ? jsonEncode(piecesDelta)
            : null,
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
  /// يستخدم `pieces_json` المهيكل أولاً، ويحتفظ بدعم `notes` للبيانات القديمة فقط
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

    final movementsAfterTarget = <Map<String, dynamic>>[];
    for (final m in allMovements) {
      final String rawDate = (m['created_at'] ?? '').toString();
      final dt = parseMovementDate(rawDate);
      if (dt != null && dt.isAfter(endOfDay)) {
        movementsAfterTarget.add(m);
      }
    }

    final result = <Map<String, dynamic>>[];

    for (final cat in currentCategories) {
      final catId = cat['id'] as int;
      final currentComps = CategoryStockHelper.parseComponents(cat['components_json']);

      final Map<String, int> pieceQuantities = {};
      final Map<String, int> pieceBaseQuantities = {};
      final Map<String, bool> pieceIsTable = {};

      for (final c in currentComps) {
        final name = (c['name'] ?? '').toString().trim();
        final int qty = CategoryStockHelper.parseInt(c['qty']);
        final int baseQty = CategoryStockHelper.parseInt(c['base_qty'], fallback: 1);
        final bool isTable = CategoryStockHelper.isTablePiece(c);
        if (name.isNotEmpty) {
          pieceQuantities[name] = qty;
          pieceBaseQuantities[name] = baseQty > 0 ? baseQty : 1;
          if (isTable) pieceIsTable[name] = true;
        }
      }

      int catStockSets = CategoryStockHelper.parseInt(cat['stock_qty']);
      final catMovementsAfter = movementsAfterTarget.where((m) => m['category_id'] == catId).toList();

      for (final m in catMovementsAfter) {
        final type = (m['movement_type'] ?? '').toString();
        final int change = CategoryStockHelper.parseInt(m['qty_change']);
        final notes = (m['notes'] ?? '').toString();

        // 1. استخدام البيانات المهيكلة `pieces_json` إن وُجدت (دقيق 100% ومستقل عن النصوص)
        final structuredPieces = CategoryStockHelper.parseComponents(m['pieces_json']);
        if (structuredPieces.isNotEmpty) {
          for (final sp in structuredPieces) {
            final pName = (sp['name'] ?? '').toString().trim();
            final delta = CategoryStockHelper.parseInt(sp['delta'], fallback: CategoryStockHelper.parseInt(sp['qty']));
            if (pName.isNotEmpty && pieceQuantities.containsKey(pName) && delta != 0) {
              // عكس التغيير: نطرح الدلتا المسجلة (إذا كانت موجبة تُخصم وإذا كانت سالبة تُضاف)
              pieceQuantities[pName] = math.max(0, pieceQuantities[pName]! - delta);
            }
          }
          continue;
        }

        // 2. التوافق مع السجلات القديمة التي لا تحتوي على pieces_json
        if (type == 'upholsterer_in' || type == 'manual_add') {
          catStockSets -= change;
          if (type == 'upholsterer_in') {
            for (final entry in pieceQuantities.entries) {
              final b = pieceBaseQuantities[entry.key] ?? 1;
              pieceQuantities[entry.key] = math.max(0, entry.value - (change * b));
            }
          }
        } else if (type == 'manual_deduct') {
          catStockSets -= change;
        } else if (type == 'delivered_out') {
          catStockSets -= change;
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
            final absSets = change.abs() > 0 ? change.abs() : 1;
            for (final entry in pieceQuantities.entries) {
              final b = pieceBaseQuantities[entry.key] ?? 1;
              pieceQuantities[entry.key] = entry.value + (absSets * b);
            }
          }
        } else if (type == 'piece_add') {
          final exp = RegExp(r'قطعة \((.*?)\)');
          final match = exp.firstMatch(notes);
          if (match != null) {
            final pName = match.group(1)?.trim() ?? '';
            if (pieceQuantities.containsKey(pName)) {
              pieceQuantities[pName] = math.max(0, pieceQuantities[pName]! - change);
            }
          }
        } else if (type == 'piece_deduct') {
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
          if (pieceIsTable[e.key] == true) 'is_table': true,
        };
      }).toList();

      final mainReconstructed = CategoryStockHelper.getMainComponents(reconstructedComps);
      if (mainReconstructed.isNotEmpty) {
        catStockSets = CategoryStockHelper.computeBreakdownFromPieces(mainReconstructed).completeSets;
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
