/// معلومات إصدار التطبيق الحالية (تُحدّث تلقائياً عند عمل Release جديد)
class AppVersion {
  static const String appName = 'موبيليا تراك';
  static const String appNameEn = 'MobilyaTrack';
  static const String version = '1.2.3';
  static const int buildNumber = 34;

  static String get displayVersion => 'v$version';
  static String get fullVersion => 'v$version ($buildNumber)';
}
