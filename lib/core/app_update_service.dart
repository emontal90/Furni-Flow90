import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version.dart';

class AppUpdateInfo {
  final String version;
  final String tagName;
  final String downloadUrl;
  final String releasePageUrl;
  final String releaseNotes;
  final int apkSize;

  String get latestVersion => version;

  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.releasePageUrl,
    required this.releaseNotes,
    required this.apkSize,
  });
}

class AppUpdateService {
  static const MethodChannel _channel =
      MethodChannel('com.furniflow.erp/app_updater');

  /// يخزن معلومات التحديث المتاح لحظياً لتحديث الواجهات وشارة الترس (Badge 1)
  static final ValueNotifier<AppUpdateInfo?> availableUpdateNotifier =
      ValueNotifier<AppUpdateInfo?>(null);

  static const String _latestReleaseApi =
      'https://api.github.com/repos/emontal90/Furni-Flow90/releases/latest';
  static const String _allowedDownloadPrefix =
      'https://github.com/emontal90/Furni-Flow90/releases/download/';
  static const String _allowedReleasePagePrefix =
      'https://github.com/emontal90/Furni-Flow90/releases/';

  static const Set<String> _trustedDownloadHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'github-releases.githubusercontent.com',
  };

  /// مقارنة رقمي إصدار بصيغة SemVer (مثلاً 1.1.0 أكبر من 1.0.28)
  static bool isVersionNewer(String remoteVersion, String currentVersion) {
    final remoteParts = _parseVersionParts(remoteVersion);
    final currentParts = _parseVersionParts(currentVersion);
    final maxLen =
        remoteParts.length > currentParts.length ? remoteParts.length : currentParts.length;

    for (var i = 0; i < maxLen; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  static List<int> _parseVersionParts(String version) {
    final cleaned = version.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    return cleaned
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  /// التحقق من وجود إصدار أحدث على GitHub Releases
  static Future<AppUpdateInfo?> checkForUpdate({bool silent = true}) async {
    if (kIsWeb) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(_latestReleaseApi);
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'FurniFlow-ERP-Android');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        if (silent) return null;
        throw HttpException('GitHub API returned status ${response.statusCode}');
      }

      final rawBody = await utf8.decodeStream(response).timeout(const Duration(seconds: 10));
      final dynamic decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        if (silent) return null;
        throw const FormatException('استجابة غير متوقعة من GitHub');
      }

      if (decoded['draft'] == true || decoded['prerelease'] == true) {
        return null;
      }

      final tagName = (decoded['tag_name'] ?? '').toString().trim();
      final remoteVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '');
      if (remoteVersion.isEmpty || !isVersionNewer(remoteVersion, AppVersion.version)) {
        availableUpdateNotifier.value = null;
        return null;
      }

      final rawHtmlUrl = (decoded['html_url'] ?? '').toString().trim();
      final releasePageUrl = rawHtmlUrl.startsWith(_allowedReleasePagePrefix)
          ? rawHtmlUrl
          : '${_allowedReleasePagePrefix}latest';

      final assets = decoded['assets'];
      String? downloadUrl;
      int apkSize = 0;

      if (assets is List) {
        Map<String, dynamic>? preferredAsset;
        Map<String, dynamic>? legacyAsset;
        Map<String, dynamic>? fallbackApkAsset;

        for (final item in assets) {
          if (item is! Map<String, dynamic>) continue;
          final name = (item['name'] ?? '').toString();
          final url = (item['browser_download_url'] ?? '').toString();
          if (!url.startsWith(_allowedDownloadPrefix)) continue;
          if (!name.toLowerCase().endsWith('.apk')) continue;

          if (name == 'FurniFlow-App.apk') {
            preferredAsset = item;
            break;
          }
          if (name == 'MobilyaTrack-App.apk') {
            preferredAsset = item;
          }

          fallbackApkAsset ??= item;
        }

        final chosen = preferredAsset ?? legacyAsset ?? fallbackApkAsset;
        if (chosen != null) {
          downloadUrl = (chosen['browser_download_url'] ?? '').toString();
          final sizeVal = chosen['size'];
          if (sizeVal is int) apkSize = sizeVal;
        }
      }

      if (downloadUrl == null) {
        if (silent) return null;
        throw Exception('تم نشر إصدار جديد ($tagName) لكن ملف التثبيت APK غير مرفق بعد.');
      }

      final info = AppUpdateInfo(
        version: remoteVersion,
        tagName: tagName,
        downloadUrl: downloadUrl,
        releasePageUrl: releasePageUrl,
        releaseNotes: (decoded['body'] ?? '').toString().trim(),
        apkSize: apkSize,
      );
      availableUpdateNotifier.value = info;
      return info;
    } catch (e) {
      if (silent) return null;
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// تنزيل ملف الـ APK من رابط GitHub الموثوق والتحقق من سلامته
  static Future<String> downloadApk(
    AppUpdateInfo update, {
    required void Function(double? progress, int receivedBytes, int totalBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('التثبيت المباشر متاح على أجهزة Android فقط.');
    }
    if (!update.downloadUrl.startsWith(_allowedDownloadPrefix)) {
      throw const HttpException('رابط التحميل غير موثوق.');
    }

    final cacheDir = await getTemporaryDirectory();
    final updatesDir = Directory('${cacheDir.path}/updates');
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }

    await for (final entity in updatesDir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    final tmpFile = File('${updatesDir.path}/furniflow-update.apk.tmp');
    final finalFile = File('${updatesDir.path}/furniflow-update.apk');

    try {
      try {
        await _channel.invokeMethod<void>('acquireWakeLock');
      } catch (_) {}

      int receivedBytes = 0;
      if (await tmpFile.exists()) {
        receivedBytes = await tmpFile.length();
      }

      int totalBytes = update.apkSize;
      int retries = 0;
      const int maxRetries = 12;

      while (retries < maxRetries) {
        if (isCancelled?.call() == true) {
          throw Exception('تم إلغاء التنزيل.');
        }

        final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
        IOSink? sink;

        try {
          Uri currentUri = Uri.parse(update.downloadUrl);
          HttpClientResponse? finalResponse;

          for (var hop = 0; hop < 6; hop++) {
            if (isCancelled?.call() == true) {
              throw Exception('تم إلغاء التنزيل.');
            }
            if (currentUri.scheme != 'https' || !_trustedDownloadHosts.contains(currentUri.host)) {
              throw HttpException('تم رفض التحويل إلى نطاق غير موثوق: ${currentUri.host}');
            }

            final req = await client.getUrl(currentUri).timeout(const Duration(seconds: 15));
            req.followRedirects = false;
            req.headers.set(HttpHeaders.userAgentHeader, 'FurniFlow-ERP-Android');
            if (receivedBytes > 0) {
              req.headers.set(HttpHeaders.rangeHeader, 'bytes=$receivedBytes-');
            }
            final resp = await req.close().timeout(const Duration(seconds: 20));

            if (resp.isRedirect ||
                resp.statusCode == HttpStatus.movedPermanently ||
                resp.statusCode == HttpStatus.found ||
                resp.statusCode == HttpStatus.seeOther ||
                resp.statusCode == HttpStatus.temporaryRedirect ||
                resp.statusCode == 308) {
              final location = resp.headers.value(HttpHeaders.locationHeader);
              await resp.drain<void>();
              if (location == null || location.isEmpty) {
                throw const HttpException('رابط التحويل فارغ.');
              }
              currentUri = currentUri.resolve(location);
              continue;
            }

            finalResponse = resp;
            break;
          }

          if (finalResponse == null) {
            throw const HttpException('تعذر الاتصال بخادم التحديث.');
          }

          final bool isPartial = finalResponse.statusCode == HttpStatus.partialContent;
          final bool isOk = finalResponse.statusCode == HttpStatus.ok;

          if (!isPartial && !isOk) {
            throw HttpException('فشل تحميل التحديث (رمز الحالة: ${finalResponse.statusCode})');
          }

          if (isOk && receivedBytes > 0) {
            receivedBytes = 0;
          }

          if (finalResponse.contentLength > 0) {
            totalBytes = isPartial
                ? receivedBytes + finalResponse.contentLength
                : finalResponse.contentLength;
          } else if (totalBytes <= 0) {
            totalBytes = update.apkSize;
          }

          sink = tmpFile.openWrite(mode: isPartial ? FileMode.append : FileMode.write);

          await for (final chunk in finalResponse) {
            if (isCancelled?.call() == true) {
              throw Exception('تم إلغاء التنزيل.');
            }
            sink.add(chunk);
            receivedBytes += chunk.length;
            final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
            onProgress(progress, receivedBytes, totalBytes);
          }

          await sink.flush();
          await sink.close();
          sink = null;

          if (totalBytes > 0 && receivedBytes >= totalBytes) {
            break;
          } else if (totalBytes <= 0 && receivedBytes > 500 * 1024) {
            break;
          }
        } catch (e) {
          try {
            await sink?.flush();
            await sink?.close();
          } catch (_) {}
          sink = null;
          client.close(force: true);

          if (isCancelled?.call() == true) {
            throw Exception('تم إلغاء التنزيل.');
          }

          retries++;
          if (retries >= maxRetries) {
            rethrow;
          }

          await Future<void>.delayed(const Duration(seconds: 2));
          if (await tmpFile.exists()) {
            receivedBytes = await tmpFile.length();
          }
          continue;
        } finally {
          client.close(force: true);
        }
      }

      if (receivedBytes < 500 * 1024) {
        throw const FormatException('الملف الذي تم تنزيله غير مكتمل أو تالف.');
      }
      if (update.apkSize > 0 && receivedBytes != update.apkSize) {
        throw const FormatException('حجم الملف لا يطابق حجم الإصدار المنشور.');
      }

      final raf = await tmpFile.open(mode: FileMode.read);
      try {
        final header = await raf.read(4);
        if (header.length < 4 ||
            header[0] != 0x50 ||
            header[1] != 0x4B ||
            header[2] != 0x03 ||
            header[3] != 0x04) {
          throw const FormatException('صيغة الملف الذي تم تنزيله ليست APK صالحاً.');
        }
      } finally {
        await raf.close();
      }

      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tmpFile.rename(finalFile.path);
      return finalFile.path;
    } finally {
      try {
        await _channel.invokeMethod<void>('releaseWakeLock');
      } catch (_) {}
    }
  }

  static Future<bool> canRequestPackageInstalls() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final res = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
    return res ?? false;
  }

  static Future<void> openUnknownAppSourcesSettings() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openUnknownAppSourcesSettings');
  }

  static Future<void> installApk(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod<void>('installApk', {'path': filePath});
  }

  static Future<void> openReleaseInBrowser(String url) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openBrowserUrl', {'url': url});
  }
}
