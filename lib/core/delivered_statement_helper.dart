import 'dart:convert';
import 'dart:math' as math;
import 'category_stock_helper.dart';
import 'order_delivery_helper.dart';
import 'upholsterer_statement_helper.dart';

/// ملخص صنف واحد داخل كشف حساب الطلبات المسلّمة
class DeliveredCategorySummary {
  final String categoryName;
  final int sets;
  final int tableSets;
  final bool isTableOnly;
  final int individualPieces;
  final int totalPieces;
  final int ordersCount;
  final Map<String, int> pieceTotals;
  final Map<String, int> excessPieceTotals;

  const DeliveredCategorySummary({
    required this.categoryName,
    required this.sets,
    this.tableSets = 0,
    this.isTableOnly = false,
    required this.individualPieces,
    required this.totalPieces,
    required this.ordersCount,
    required this.pieceTotals,
    required this.excessPieceTotals,
  });
}

/// سجل طلبية واحدة مسلّمة ضمن الكشف
class DeliveredOrderStatementItem {
  final String deliveryDate;
  final String customerName;
  final String categoryName;
  final String orderType;
  final int sets;
  final int tableSets;
  final bool isTableOnly;
  final int individualPieces;
  final int totalPieces;
  final List<Map<String, dynamic>> pieces;
  final String? statusBadge;

  const DeliveredOrderStatementItem({
    required this.deliveryDate,
    required this.customerName,
    required this.categoryName,
    required this.orderType,
    required this.sets,
    this.tableSets = 0,
    this.isTableOnly = false,
    required this.individualPieces,
    required this.totalPieces,
    required this.pieces,
    this.statusBadge,
  });
}

/// التقرير الكامل لكشف حساب الطلبات التي تم تسليمها
class DeliveredStatementReport {
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? categoryFilter;
  final String? customerFilter;
  final int totalSets;
  final int totalTableSets;
  final int totalIndividualPieces;
  final int totalPieces;
  final int ordersCount;
  final int totalOrdersBeforeDateFilter;
  final List<DeliveredCategorySummary> categorySummaries;
  final List<DeliveredOrderStatementItem> items;

  const DeliveredStatementReport({
    required this.fromDate,
    required this.toDate,
    required this.categoryFilter,
    required this.customerFilter,
    required this.totalSets,
    this.totalTableSets = 0,
    required this.totalIndividualPieces,
    required this.totalPieces,
    required this.ordersCount,
    required this.totalOrdersBeforeDateFilter,
    required this.categorySummaries,
    required this.items,
  });

  bool get isEmpty => ordersCount == 0 && totalPieces == 0;
}

class DeliveredStatementHelper {
  static DeliveredStatementReport buildStatement({
    required List<Map<String, dynamic>> deliveredOrders,
    required List<Map<String, dynamic>> categories,
    DateTime? fromDate,
    DateTime? toDate,
    String? categoryNameFilter,
    String? customerNameFilter,
  }) {
    final Map<int, List<dynamic>> compsById = {};
    final Map<String, List<dynamic>> compsByName = {};
    for (final cat in categories) {
      final int id = CategoryStockHelper.parseInt(cat['id']);
      final String name = (cat['name'] ?? '').toString().trim();
      final List<dynamic> comps = CategoryStockHelper.parseComponents(cat['components_json']);
      if (id > 0) compsById[id] = comps;
      if (name.isNotEmpty) compsByName[name] = comps;
    }

    final String? cleanCatFilter =
        (categoryNameFilter != null && categoryNameFilter.trim().isNotEmpty && categoryNameFilter != 'all')
            ? categoryNameFilter.trim()
            : null;
    final String? cleanCustFilter =
        (customerNameFilter != null && customerNameFilter.trim().isNotEmpty && customerNameFilter != 'all')
            ? customerNameFilter.trim()
            : null;

    // 1. فلترة الصنف والعميل
    final matchingEntityOrders = deliveredOrders.where((o) {
      final catName = (o['category_name'] ?? '').toString().trim();
      final custName = (o['customer_name'] ?? '').toString().trim();
      if (cleanCatFilter != null && catName != cleanCatFilter) return false;
      if (cleanCustFilter != null && custName != cleanCustFilter) return false;
      return true;
    }).toList();

    // 2. فلترة التاريخ (من - إلى)
    final DateTime? startBound =
        fromDate != null ? DateTime(fromDate.year, fromDate.month, fromDate.day) : null;
    final DateTime? endBound =
        toDate != null ? DateTime(toDate.year, toDate.month, toDate.day) : null;

    final filteredOrders = matchingEntityOrders.where((o) {
      if (startBound == null && endBound == null) return true;
      final d = UpholstererStatementHelper.parseDateOnly(
        (o['delivery_date'] ?? o['created_at'] ?? '').toString(),
      );
      if (d == null) return false;
      if (startBound != null && d.isBefore(startBound)) return false;
      if (endBound != null && d.isAfter(endBound)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final da = UpholstererStatementHelper.parseDateOnly((a['delivery_date'] ?? '').toString());
        final db = UpholstererStatementHelper.parseDateOnly((b['delivery_date'] ?? '').toString());
        if (da != null && db != null) return db.compareTo(da);
        return (b['delivery_date'] ?? '').toString().compareTo((a['delivery_date'] ?? '').toString());
      });

    final Map<String, List<Map<String, dynamic>>> ordersByCat = {};
    final List<DeliveredOrderStatementItem> items = [];

    for (final o in filteredOrders) {
      final int catId = CategoryStockHelper.parseInt(o['category_id']);
      final String catName = (o['category_name'] ?? '').toString().trim();
      final String custName = (o['customer_name'] ?? '').toString().trim();
      final String orderType = (o['order_type'] ?? '').toString().trim();
      final String dateStr = (o['delivery_date'] ?? '').toString().trim();
      final int setsFallback = CategoryStockHelper.parseInt(o['sets_count'], fallback: 1);

      final List<dynamic> rawCatComps = (catId > 0 && compsById.containsKey(catId))
          ? compsById[catId]!
          : (compsByName[catName] ?? const []);

      List<dynamic> rawOrderComps = const [];
      try {
        final decoded = jsonDecode((o['selected_components_json'] ?? '[]').toString());
        if (decoded is List) rawOrderComps = decoded;
      } catch (_) {}

      final pieces = OrderDeliveryHelper.extractOrderPieces(
        rawOrderComps,
        rawCatComps,
        setsCount: setsFallback,
      );
      final summary = OrderDeliveryHelper.summarizeOrder(
        orderComps: pieces,
        rawCategoryComps: rawCatComps,
        fallbackSetsCount: setsFallback,
      );

      final bool isTableOnly = OrderDeliveryHelper.isTableSetOnlyOrder(pieces);
      final String? statusBadge = summary.toStatusBadgeLabel(isTableOnly: isTableOnly);
      final catKey = isTableOnly
          ? 'طقم ترابيزات : "${catName.isNotEmpty ? catName : 'صنف #$catId'}"'
          : (catName.isNotEmpty ? catName : 'صنف #$catId');
      ordersByCat.putIfAbsent(catKey, () => []).add({
        'category_id': catId,
        'pieces': pieces,
        'is_table_only': isTableOnly,
      });

      items.add(DeliveredOrderStatementItem(
        deliveryDate: dateStr,
        customerName: custName,
        categoryName: catKey,
        orderType: orderType,
        sets: isTableOnly ? 0 : summary.sets,
        tableSets: isTableOnly ? summary.sets : 0,
        isTableOnly: isTableOnly,
        individualPieces: summary.individualPieces,
        totalPieces: summary.totalPieces,
        pieces: pieces,
        statusBadge: statusBadge,
      ));
    }

    int totalSets = 0;
    int totalTableSets = 0;
    int totalIndividual = 0;
    int totalPieces = 0;
    final List<DeliveredCategorySummary> catSummaries = [];

    final sortedCats = ordersByCat.keys.toList()..sort();
    for (final catName in sortedCats) {
      final list = ordersByCat[catName]!;
      final bool isCatTableOnly = catName.startsWith('طقم ترابيزات :');
      final int refCatId = CategoryStockHelper.parseInt(list.first['category_id']);
      final List<dynamic> rawCatComps = (refCatId > 0 && compsById.containsKey(refCatId))
          ? compsById[refCatId]!
          : (compsByName[catName] ?? const []);

      final Map<String, int> pieceTotals = {};
      final Map<String, int> baseByName = {};
      final Set<String> customNames = {};
      final Set<String> tableNames = {};

      for (final entry in list) {
        final pieces = entry['pieces'] as List<Map<String, dynamic>>;
        for (final p in pieces) {
          final pName = (p['name'] ?? '').toString().trim();
          final qty = math.max(0, CategoryStockHelper.parseInt(p['qty']));
          if (pName.isEmpty || qty <= 0) continue;
          pieceTotals[pName] = (pieceTotals[pName] ?? 0) + qty;
          if (p['is_table'] == true || p['is_table'] == 1) {
            tableNames.add(pName);
          }
          if (p['is_custom'] == true) {
            customNames.add(pName);
            baseByName[pName] = 0;
          } else {
            final b = CategoryStockHelper.parseInt(p['base_qty'], fallback: 1);
            baseByName.putIfAbsent(pName, () => b > 0 ? b : 1);
          }
        }
      }

      final mergedComps = pieceTotals.entries
          .map((e) => {
                'name': e.key,
                'qty': e.value,
                'base_qty': baseByName[e.key] ?? 1,
                if (tableNames.contains(e.key) || isCatTableOnly) 'is_table': true,
                if (customNames.contains(e.key)) 'is_custom': true,
              })
          .toList();

      final catSummary = OrderDeliveryHelper.summarizeOrder(
        orderComps: mergedComps,
        rawCategoryComps: rawCatComps,
      );

      final Map<String, int> baseLookup = {};
      for (final item in rawCatComps) {
        if (item is! Map) continue;
        if (isCatTableOnly && item['is_table'] != true && item['is_table'] != 1) continue;
        final n = (item['name'] ?? '').toString().trim();
        final b = math.max(1, CategoryStockHelper.parseInt(item['base_qty'], fallback: 1));
        if (n.isNotEmpty) baseLookup[n] = b;
      }

      final Map<String, int> excessPieces = {};
      for (final entry in pieceTotals.entries) {
        final int base = customNames.contains(entry.key)
            ? 0
            : (baseLookup[entry.key] ?? (rawCatComps.isEmpty ? (baseByName[entry.key] ?? 0) : 0));
        final int excess = base > 0
            ? math.max(0, entry.value - catSummary.sets * base)
            : entry.value;
        if (excess > 0) {
          excessPieces[entry.key] = excess;
        }
      }

      if (isCatTableOnly) {
        totalTableSets += catSummary.sets;
      } else {
        totalSets += catSummary.sets;
      }
      totalIndividual += catSummary.individualPieces;
      totalPieces += catSummary.totalPieces;

      catSummaries.add(DeliveredCategorySummary(
        categoryName: catName,
        sets: isCatTableOnly ? 0 : catSummary.sets,
        tableSets: isCatTableOnly ? catSummary.sets : 0,
        isTableOnly: isCatTableOnly,
        individualPieces: catSummary.individualPieces,
        totalPieces: catSummary.totalPieces,
        ordersCount: list.length,
        pieceTotals: pieceTotals,
        excessPieceTotals: excessPieces,
      ));
    }

    return DeliveredStatementReport(
      fromDate: startBound,
      toDate: endBound,
      categoryFilter: cleanCatFilter,
      customerFilter: cleanCustFilter,
      totalSets: totalSets,
      totalTableSets: totalTableSets,
      totalIndividualPieces: totalIndividual,
      totalPieces: totalPieces,
      ordersCount: items.length,
      totalOrdersBeforeDateFilter: matchingEntityOrders.length,
      categorySummaries: catSummaries,
      items: items,
    );
  }
}
