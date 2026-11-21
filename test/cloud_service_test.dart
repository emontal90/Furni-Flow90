import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/cloud_service.dart';
import 'package:furniture_erp/core/license_service.dart';

void main() {
  group('SubscriptionPlan and CloudService Tests', () {
    test('SubscriptionPlan constants match requirements', () {
      expect(SubscriptionPlan.plans.length, 3);

      final monthly = SubscriptionPlan.plans.firstWhere((p) => p.id == 'monthly');
      expect(monthly.days, 30);
      expect(monthly.price, 300);

      final halfYearly = SubscriptionPlan.plans.firstWhere((p) => p.id == 'half_yearly');
      expect(halfYearly.days, 180);
      expect(halfYearly.price, 1800);

      final yearly = SubscriptionPlan.plans.firstWhere((p) => p.id == 'yearly');
      expect(yearly.days, 365);
      expect(yearly.price, 3500);
    });

    test('CloudSubscriptionData calculates remaining days and status getters accurately', () {
      final now = DateTime.now();
      final futureExpiry = now.add(const Duration(days: 45));

      final activeSub = CloudSubscriptionData(
        deviceCode: 'MT-1234-5678-90AB',
        status: 'active',
        planDays: 45,
        expiresAt: futureExpiry,
      );

      expect(activeSub.isActive, isTrue);
      expect(activeSub.isPending, isFalse);
      expect(activeSub.isPaused, isFalse);
      expect(activeSub.daysRemaining, inInclusiveRange(44, 45));

      const pausedSub = CloudSubscriptionData(
        deviceCode: 'MT-1234-5678-90AB',
        status: 'paused',
      );
      expect(pausedSub.isPaused, isTrue);
      expect(pausedSub.isActive, isFalse);
    });

    test('CloudBackupItem parses json with formatted sizes and auto flags properly', () {
      final json = {
        'id': 'abc-123',
        'device_code': 'MT-TEST-0001',
        'file_name': 'cloud_manual_test.mtbk',
        'storage_path': 'MT-TEST-0001/cloud_manual_test.mtbk',
        'file_size_bytes': 1024 * 50,
        'file_size_formatted': '50.0 KB',
        'is_auto': true,
        'created_at': DateTime(2026, 11, 22).toIso8601String(),
      };

      final item = CloudBackupItem.fromJson(json);
      expect(item.id, 'abc-123');
      expect(item.deviceCode, 'MT-TEST-0001');
      expect(item.isAuto, isTrue);
      expect(item.fileSizeFormatted, '50.0 KB');
    });

    test('Cryptographic key generation matches between Flutter and Python/Portal HMAC specs', () {
      const device = 'MT-AAAA-BBBB-CCCC';
      const expiry = '20271231';
      final generatedKey = LicenseService.generateKeyForDevice(device, expiryToken: expiry);
      expect(generatedKey.startsWith('MTK-20271231-'), isTrue);

      final validation = LicenseService.validateKey(deviceCode: device, rawKey: generatedKey);
      expect(validation.valid, isTrue);
      expect(validation.expiresAt?.year, 2027);
    });
  });
}
