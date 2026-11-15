import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/stock_movement_helper.dart';

void main() {
  group('StockMovementHelper', () {
    test('parseMovementDate correctly parses various Arabic and ISO formats', () {
      final d1 = StockMovementHelper.parseMovementDate('2026-11-15 10:30:00 ص');
      expect(d1, isNotNull);
      expect(d1!.year, 2026);
      expect(d1.month, 11);
      expect(d1.day, 15);
      expect(d1.hour, 10);
      expect(d1.minute, 30);

      final d2 = StockMovementHelper.parseMovementDate('2026-11-15 10:30:00 م');
      expect(d2, isNotNull);
      expect(d2!.hour, 22);

      final d3 = StockMovementHelper.parseMovementDate('2026-11-15 12:15:00 ص');
      expect(d3, isNotNull);
      expect(d3!.hour, 0);

      final d4 = StockMovementHelper.parseMovementDate('2026-11-15 12:15:00 م');
      expect(d4, isNotNull);
      expect(d4!.hour, 12);

      final d5 = StockMovementHelper.parseMovementDate('2026-11-15T18:00:00.000Z');
      expect(d5, isNotNull);
      expect(d5!.day, 15);

      final d6 = StockMovementHelper.parseMovementDate('invalid');
      expect(d6, isNull);
    });

    test('getStockAtEndOfDate reverses movements created after target date', () async {
      final currentCategories = [
        {
          'id': 1,
          'name': 'طقم مودرن',
          'sets_count': 5,
          'components_json': jsonEncode([
            {'name': 'كنبة كبيرة', 'base_qty': 1, 'qty': 5},
            {'name': 'فوتيه', 'base_qty': 2, 'qty': 10},
          ]),
        },
      ];

      // If on 2026-11-16 (after 2026-11-15 23:59:59), we added 2 sets (upholsterer_in):
      // Then at end of 2026-11-15, we had 5 - 2 = 3 sets.
      final movements = [
        {
          'category_id': 1,
          'movement_type': 'upholsterer_in',
          'qty_change': 2,
          'created_at': '2026-11-16 02:00:00 م',
          'notes': 'استلام 2 طقم',
        },
      ];

      final targetDate = DateTime(2026, 11, 15);
      final reconstructed = await StockMovementHelper.getStockAtEndOfDate(
        currentCategories: currentCategories,
        targetDate: targetDate,
        mockMovements: movements,
      );

      expect(reconstructed.length, 1);
      expect(reconstructed[0]['stock_qty'], 3);
      final comps = jsonDecode(reconstructed[0]['components_json']) as List;
      expect(comps.firstWhere((c) => c['name'] == 'كنبة كبيرة')['qty'], 3);
      expect(comps.firstWhere((c) => c['name'] == 'فوتيه')['qty'], 6);
    });
  });
}
