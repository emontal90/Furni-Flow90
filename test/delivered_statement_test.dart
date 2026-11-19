import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/category_stock_helper.dart';
import 'package:furniture_erp/core/delivered_statement_helper.dart';

void main() {
  final categories = [
    {
      'id': 1,
      'name': 'جلاكسي',
      'components_json': jsonEncode([
        {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 0},
        {'name': 'كنبة صغيرة', 'base_qty': 1, 'qty': 0},
        {'name': 'فوتيه', 'base_qty': 2, 'qty': 0},
      ]),
    },
  ];

  test('CategoryStockHelper computes 1 complete set + 3 individual pieces when 1 sofa is taken from 2 sets', () {
    final afterTakingOneSofa = [
      {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 1},
      {'name': 'كنبة صغيرة', 'base_qty': 1, 'qty': 2},
      {'name': 'فوتيه', 'base_qty': 2, 'qty': 4},
    ];
    final breakdown = CategoryStockHelper.computeBreakdownFromPieces(
      afterTakingOneSofa,
      qtyKey: 'qty',
      expectedComponentCount: 3,
    );
    expect(breakdown.completeSets, 1);
    expect(breakdown.individualPieces, 3);
    expect(breakdown.totalPieces, 7);
  });

  test('DeliveredStatementHelper aggregates sets and individual pieces with customer and category filters', () {
    final orders = [
      {
        'id': 1,
        'customer_name': 'أحمد محمود',
        'category_id': 1,
        'category_name': 'جلاكسي',
        'order_type': 'نمطي',
        'sets_count': 1,
        'delivery_date': '2026-11-18',
        'selected_components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'qty': 1, 'base_qty': 1},
          {'name': 'كنبة صغيرة', 'qty': 1, 'base_qty': 1},
          {'name': 'فوتيه', 'qty': 3, 'base_qty': 2},
        ]),
      },
      {
        'id': 2,
        'customer_name': 'كريم سعيد',
        'category_id': 1,
        'category_name': 'جلاكسي',
        'order_type': 'أوردر',
        'sets_count': 1,
        'delivery_date': '2026-11-19',
        'selected_components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'qty': 1, 'base_qty': 1},
          {'name': 'كنبة صغيرة', 'qty': 1, 'base_qty': 1},
          {'name': 'فوتيه', 'qty': 2, 'base_qty': 2},
        ]),
      },
    ];

    final allReport = DeliveredStatementHelper.buildStatement(
      deliveredOrders: orders,
      categories: categories,
      fromDate: DateTime(2026, 11, 1),
      toDate: DateTime(2026, 11, 20),
    );
    expect(allReport.ordersCount, 2);
    expect(allReport.totalSets, 2);
    expect(allReport.totalIndividualPieces, 1);
    expect(allReport.totalPieces, 9);

    final custReport = DeliveredStatementHelper.buildStatement(
      deliveredOrders: orders,
      categories: categories,
      customerNameFilter: 'أحمد محمود',
    );
    expect(custReport.ordersCount, 1);
    expect(custReport.totalSets, 1);
    expect(custReport.totalIndividualPieces, 1);
  });
}
