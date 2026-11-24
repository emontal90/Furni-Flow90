/// معلومات إصدار التطبيق الحالية (تُحدّث تلقائياً عند عمل Release جديد)
class AppVersion {
  static const String appName = 'فورني فلو';
  static const String appNameEn = 'FurniFlow';
  static const String version = '1.2.14';
  static const int buildNumber = 45;

  static String get displayVersion => 'v$version';
  static String get fullVersion => 'v$version ($buildNumber)';
}
