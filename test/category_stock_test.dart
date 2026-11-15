import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/category_stock_helper.dart';

void main() {
  group('CategoryStockHelper', () {
    test('calculateCompleteSets calculates sets accurately based on base_qty', () {
      final cat = {
        'id': 1,
        'name': 'طقم كنز',
        'stock_qty': 0, // In DB it was 0, but pieces actually form 2 sets!
        'components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 2},
          {'name': 'كنبة صغيرة', 'base_qty': 1, 'qty': 3}, // 1 excess
          {'name': 'فوتيه', 'base_qty': 2, 'qty': 4},
        ]),
      };

      expect(CategoryStockHelper.calculateCompleteSets(cat), 2);
      expect(CategoryStockHelper.calculateIndividualPieces(cat), 1);
      expect(CategoryStockHelper.formatStockSummary(cat), '2 طقم و 1 فردي');
      expect(
        CategoryStockHelper.formatDropdownItem(cat),
        'طقم كنز (رصيد المعرض: 2 طقم و 1 فردي)',
      );
    });

    test('handles 0 complete sets with individual pieces', () {
      final cat = {
        'id': 2,
        'name': 'طقم ماسة',
        'stock_qty': 0,
        'components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 0},
          {'name': 'فوتيه', 'base_qty': 2, 'qty': 3},
        ]),
      };

      expect(CategoryStockHelper.calculateCompleteSets(cat), 0);
      expect(CategoryStockHelper.calculateIndividualPieces(cat), 3);
      expect(CategoryStockHelper.formatStockSummary(cat), '3 فردي');
      expect(
        CategoryStockHelper.formatDropdownItem(cat),
        'طقم ماسة (رصيد المعرض: 3 فردي)',
      );
    });

    test('handles complete sets only with no individual pieces', () {
      final cat = {
        'id': 3,
        'name': 'طقم كابوتكا',
        'stock_qty': 5,
        'components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 5},
          {'name': 'فوتيه', 'base_qty': 2, 'qty': 10},
        ]),
      };

      expect(CategoryStockHelper.calculateCompleteSets(cat), 5);
      expect(CategoryStockHelper.calculateIndividualPieces(cat), 0);
      expect(CategoryStockHelper.formatStockSummary(cat), '5 طقم');
      expect(
        CategoryStockHelper.formatDropdownItem(cat),
        'طقم كابوتكا (رصيد المعرض: 5 طقم)',
      );
    });

    test('handles empty / zero stock', () {
      final cat = {
        'id': 4,
        'name': 'طقم فارغ',
        'stock_qty': 0,
        'components_json': jsonEncode([
          {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 0},
          {'name': 'فوتيه', 'base_qty': 2, 'qty': 0},
        ]),
      };

      expect(CategoryStockHelper.calculateCompleteSets(cat), 0);
      expect(CategoryStockHelper.calculateIndividualPieces(cat), 0);
      expect(CategoryStockHelper.formatStockSummary(cat), '0 طقم');
      expect(
        CategoryStockHelper.formatDropdownItem(cat),
        'طقم فارغ (رصيد المعرض: 0 طقم)',
      );
    });
  });
}

