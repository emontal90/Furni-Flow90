import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/backup_crypto.dart';
import 'package:furniture_erp/core/license_service.dart';
import 'package:furniture_erp/core/stock_movement_helper.dart';

void main() {
  group('BackupCrypto (AES-256-CTR + HMAC-SHA256)', () {
    test('encrypts and decrypts binary data accurately', () {
      final sample = Uint8List.fromList(utf8.encode('SQLite format 3\u0000' + 'MobilyaTrackData' * 20));
      final encrypted = BackupCrypto.encryptBytes(sample);

      expect(BackupCrypto.isEncryptedBytes(encrypted), isTrue);
      expect(encrypted, isNot(equals(sample)));

      final decrypted = BackupCrypto.decryptBytes(encrypted);
      expect(decrypted, equals(sample));
    });

    test('rejects tampered encrypted payload and wrong passphrase', () {
      final sample = Uint8List.fromList(utf8.encode('Confidential Showroom DB'));
      final encrypted = BackupCrypto.encryptBytes(sample, passphrase: 'SecretPassword123');

      // Wrong passphrase must throw
      expect(
        () => BackupCrypto.decryptBytes(encrypted, passphrase: 'WrongPassword'),
        throwsFormatException,
      );

      // Tampering a single byte must fail HMAC verification
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 40] ^= 0xFF;
      expect(
        () => BackupCrypto.decryptBytes(tampered, passphrase: 'SecretPassword123'),
        throwsFormatException,
      );
    });
  });

  group('LicenseService (Device-Bound Commercial Keys)', () {
    test('validates matching device permanent and dated license keys and rejects mismatched devices', () {
      const deviceA = 'MT-1A2B-3C4D-5E6F';
      const deviceB = 'MT-9999-8888-7777';

      final permKey = LicenseService.generateKeyForDevice(deviceA, expiryToken: 'PERM');
      final validRes = LicenseService.validateKey(deviceCode: deviceA, rawKey: permKey);
      expect(validRes.valid, isTrue);
      expect(validRes.isPermanent, isTrue);

      final wrongDeviceRes = LicenseService.validateKey(deviceCode: deviceB, rawKey: permKey);
      expect(wrongDeviceRes.valid, isFalse);

      final expiredKey = LicenseService.generateKeyForDevice(deviceA, expiryToken: '20200101');
      final expiredRes = LicenseService.validateKey(deviceCode: deviceA, rawKey: expiredKey);
      expect(expiredRes.valid, isFalse);
    });
  });

  group('StockMovementHelper structured pieces_json history', () {
    test('reconstructs historical stock accurately from pieces_json without relying on Arabic Regex', () async {
      final currentCategories = [
        {
          'id': 1,
          'name': 'طقم ملكي',
          'stock_qty': 2,
          'components_json': jsonEncode([
            {'name': 'كنبة (كبير)', 'base_qty': 1, 'qty': 2},
            {'name': 'فوتيه', 'base_qty': 2, 'qty': 4},
          ]),
        },
      ];

      final movements = [
        {
          'category_id': 1,
          'movement_type': 'delivered_out',
          'qty_change': -1,
          'created_at': '2026-11-18 03:00 م',
          'notes': 'تسليم مخصص بدون نص قياسي',
          'pieces_json': jsonEncode([
            {'name': 'كنبة (كبير)', 'delta': -1},
            {'name': 'فوتيه', 'delta': -2},
          ]),
        },
      ];

      final reconstructed = await StockMovementHelper.getStockAtEndOfDate(
        currentCategories: currentCategories,
        targetDate: DateTime(2026, 11, 17),
        mockMovements: movements,
      );

      expect(reconstructed.first['stock_qty'], 3);
      final comps = jsonDecode(reconstructed.first['components_json']) as List;
      expect(comps.firstWhere((c) => c['name'] == 'كنبة (كبير)')['qty'], 3);
      expect(comps.firstWhere((c) => c['name'] == 'فوتيه')['qty'], 6);
    });
  });
}
