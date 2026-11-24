import 'dart:convert';
import 'category_stock_helper.dart';
import 'stock_movement_helper.dart';

/// ملخص صنف واحد داخل كشف حساب مخزن المعرض
class ShowroomCategorySummary {
  final String categoryName;
  final int currentSets;
  final int currentTableSets;
  final int currentIndividualPieces;
  final int currentTotalPieces;
  final int movementsCount;
  final int incomingCount;
  final int outgoingCount;

  const ShowroomCategorySummary({
    required this.categoryName,
    required this.currentSets,
    this.currentTableSets = 0,
    required this.currentIndividualPieces,
    required this.currentTotalPieces,
    required this.movementsCount,
    required this.incomingCount,
    required this.outgoingCount,
  });
}

/// سجل حركة مخزن واحدة ضمن الكشف
class ShowroomMovementStatementItem {
  final String dateDisplay;
  final String categoryName;
  final String movementType;
  final String typeLabel;
  final bool isIncoming;
  final bool isOutgoing;
  final int qtyChange;
  final int stockAfter;
  final String notes;

  const ShowroomMovementStatementItem({
    required this.dateDisplay,
    required this.categoryName,
    required this.movementType,
    required this.typeLabel,
    required this.isIncoming,
    required this.isOutgoing,
    required this.qtyChange,
    required this.stockAfter,
    required this.notes,
  });
}

/// التقرير الكامل لكشف حساب مخزن المعرض
class ShowroomStatementReport {
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? categoryFilter;
  final String typeFilter;
  final int totalCurrentSets;
  final int totalCurrentIndividualPieces;
  final int totalCurrentPieces;
  final int incomingCount;
  final int outgoingCount;
  final int movementsCount;
  final int totalMovementsBeforeDateFilter;
  final List<ShowroomCategorySummary> categorySummaries;
  final List<ShowroomMovementStatementItem> items;

  const ShowroomStatementReport({
    required this.fromDate,
    required this.toDate,
    required this.categoryFilter,
    required this.typeFilter,
    required this.totalCurrentSets,
    required this.totalCurrentIndividualPieces,
    required this.totalCurrentPieces,
    required this.incomingCount,
    required this.outgoingCount,
    required this.movementsCount,
    required this.totalMovementsBeforeDateFilter,
    required this.categorySummaries,
    required this.items,
  });

  bool get isEmpty => movementsCount == 0 && categorySummaries.isEmpty;
}

class ShowroomStatementHelper {
  static String movementTypeLabel(String type) {
    switch (type) {
      case 'delivered_out':
        return 'تسليم أوردر للعميل (خصم)';
      case 'upholsterer_in':
        return 'استلام من المنجد (إضافة)';
      case 'upholsterer_out':
        return 'تسليم للمنجد للتشطيب';
      case 'upholsterer_balance_adjust':
        return 'تعديل رصيد لدى المنجد';
      case 'manual_add':
        return 'إضافة رصيد طقم بالمخزن (+)';
      case 'manual_deduct':
        return 'إنقاص رصيد طقم بالمخزن (-)';
      case 'piece_add':
        return 'إضافة رصيد قطع للطقم (+)';
      case 'piece_deduct':
        return 'إنقاص عدد قطع الطقم (-)';
      default:
        return 'تعديل رصيد المخزن';
    }
  }

  static bool isIncomingType(String type, int qtyChange) {
    if (type == 'upholsterer_in' || type == 'manual_add' || type == 'piece_add') {
      return true;
    }
    return qtyChange > 0;
  }

  static bool isOutgoingType(String type, int qtyChange) {
    if (type == 'delivered_out' ||
        type == 'manual_deduct' ||
        type == 'piece_deduct' ||
        type == 'upholsterer_out') {
      return true;
    }
    return qtyChange < 0;
  }

  static ShowroomStatementReport buildStatement({
    required List<Map<String, dynamic>> movements,
    required List<Map<String, dynamic>> categories,
    DateTime? fromDate,
    DateTime? toDate,
    String? categoryNameFilter,
    String typeFilter = 'all',
  }) {
    final String? cleanCatFilter = (categoryNameFilter != null &&
            categoryNameFilter.trim().isNotEmpty &&
            categoryNameFilter != 'all')
        ? categoryNameFilter.trim()
        : null;

    final DateTime? fromDay = fromDate != null
        ? DateTime(fromDate.year, fromDate.month, fromDate.day)
        : null;
    final DateTime? toDayEnd = toDate != null
        ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59)
        : null;

    int totalCurrentSets = 0;
    int totalCurrentInd = 0;
    int totalCurrentPieces = 0;

    final Map<String, ({int sets, int tableSets, int ind, int total})> stockByCat = {};
    for (final cat in categories) {
      final String name = (cat['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (cleanCatFilter != null && name != cleanCatFilter) continue;

      final List<dynamic> comps = CategoryStockHelper.parseComponents(cat['components_json']);
      final mainComps = CategoryStockHelper.getMainComponents(comps);
      final tableComps = CategoryStockHelper.getTableComponents(comps);

      final mainBreak = CategoryStockHelper.computeBreakdownFromPieces(
        mainComps,
        qtyKey: 'qty',
        expectedComponentCount: mainComps.length,
      );
      final tableBreak = CategoryStockHelper.computeBreakdownFromPieces(
        tableComps,
        qtyKey: 'qty',
        expectedComponentCount: tableComps.length,
      );

      final int sets = mainBreak.completeSets;
      final int ind = mainBreak.individualPieces;
      final int total = mainBreak.totalPieces + tableBreak.totalPieces;

      totalCurrentSets += sets;
      totalCurrentInd += ind;
      totalCurrentPieces += total;

      stockByCat[name] = (
        sets: sets,
        tableSets: tableBreak.completeSets,
        ind: ind,
        total: total,
      );
    }

    int totalBeforeDateFilter = 0;
    int incomingCount = 0;
    int outgoingCount = 0;
    final Map<String, ({int count, int inc, int out})> movStatsByCat = {};
    final List<ShowroomMovementStatementItem> items = [];

    for (final mov in movements) {
      final String catName = (mov['category_name'] ?? '').toString().trim();
      if (cleanCatFilter != null && catName != cleanCatFilter) continue;

      final String type = (mov['movement_type'] ?? '').toString().trim();
      final int change = CategoryStockHelper.parseInt(mov['qty_change']);
      final bool inc = isIncomingType(type, change);
      final bool out = isOutgoingType(type, change);

      if (typeFilter == 'in' && !inc) continue;
      if (typeFilter == 'out' && !out) continue;

      totalBeforeDateFilter++;

      final String rawDate = (mov['created_at'] ?? '').toString();
      final DateTime? parsedDate = StockMovementHelper.parseMovementDate(rawDate);
      if (fromDay != null && (parsedDate == null || parsedDate.isBefore(fromDay))) {
        continue;
      }
      if (toDayEnd != null && (parsedDate == null || parsedDate.isAfter(toDayEnd))) {
        continue;
      }

      if (inc) incomingCount++;
      if (out) outgoingCount++;

      final prev = movStatsByCat[catName] ?? (count: 0, inc: 0, out: 0);
      movStatsByCat[catName] = (
        count: prev.count + 1,
        inc: prev.inc + (inc ? 1 : 0),
        out: prev.out + (out ? 1 : 0),
      );

      String notes = (mov['notes'] ?? '').toString().trim();
      final String piecesRaw = (mov['pieces_json'] ?? '').toString().trim();
      if (notes.isEmpty && piecesRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(piecesRaw);
          if (decoded is List) {
            notes = decoded
                .whereType<Map>()
                .map((p) => '${p['name']}: ${p['delta']}')
                .join(' • ');
          }
        } catch (_) {}
      }

      items.add(
        ShowroomMovementStatementItem(
          dateDisplay: StockMovementHelper.formatDateString12(rawDate),
          categoryName: catName,
          movementType: type,
          typeLabel: movementTypeLabel(type),
          isIncoming: inc,
          isOutgoing: out,
          qtyChange: change,
          stockAfter: CategoryStockHelper.parseInt(mov['stock_after']),
          notes: notes,
        ),
      );
    }

    final Set<String> allCatNames = {...stockByCat.keys, ...movStatsByCat.keys};
    final List<ShowroomCategorySummary> summaries = allCatNames.map((name) {
      final st = stockByCat[name];
      final mv = movStatsByCat[name];
      return ShowroomCategorySummary(
        categoryName: name,
        currentSets: st?.sets ?? 0,
        currentTableSets: st?.tableSets ?? 0,
        currentIndividualPieces: st?.ind ?? 0,
        currentTotalPieces: st?.total ?? 0,
        movementsCount: mv?.count ?? 0,
        incomingCount: mv?.inc ?? 0,
        outgoingCount: mv?.out ?? 0,
      );
    }).toList()
      ..sort((a, b) => a.categoryName.compareTo(b.categoryName));

    return ShowroomStatementReport(
      fromDate: fromDate,
      toDate: toDate,
      categoryFilter: cleanCatFilter,
      typeFilter: typeFilter,
      totalCurrentSets: totalCurrentSets,
      totalCurrentIndividualPieces: totalCurrentInd,
      totalCurrentPieces: totalCurrentPieces,
      incomingCount: incomingCount,
      outgoingCount: outgoingCount,
      movementsCount: items.length,
      totalMovementsBeforeDateFilter: totalBeforeDateFilter,
      categorySummaries: summaries,
      items: items,
    );
  }
}
