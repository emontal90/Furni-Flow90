import 'package:flutter_test/flutter_test.dart';
import 'package:furniture_erp/core/app_version.dart';

void main() {
  test('AppVersion sanity check', () {
    expect(AppVersion.appName, 'موبيليا تراك');
    expect(AppVersion.appNameEn, 'MobilyaTrack');
    expect(AppVersion.version, isNotEmpty);
    expect(AppVersion.displayVersion, contains('v1.'));
  });
}
