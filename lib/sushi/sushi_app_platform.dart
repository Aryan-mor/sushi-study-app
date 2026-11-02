import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Shelf keys stored in `app_releases` / main-bot Download (ADR 0019).
const sushiPlatAndroidNew = 'android_new';
const sushiPlatAndroidOld = 'android_old';
const sushiPlatAndroidTV = 'android_tv';
const sushiPlatWindows = 'windows';
const sushiPlatLinux = 'linux';
const sushiPlatMacOS = 'macos';
const sushiPlatIOS = 'ios';

/// Caption stamped on the protocol-chat copy. Mirror of `api.AppUpdateLocator`.
///
/// [version] keeps each shelf build distinct. A bare `app_windows` caption made the
/// downloader reuse the previous setup already sitting in the protocol chat.
String sushiAppUpdateLocator(String platform, [String version = '']) {
  final v = version.trim();
  if (v.isEmpty) return 'app_$platform';
  return 'app_${platform}_${v}_';
}

/// Client's `app_releases` platform. Empty on web / unknown.
Future<String> sushiAppPlatform() async {
  if (kIsWeb) return '';
  if (Platform.isWindows) return sushiPlatWindows;
  if (Platform.isLinux) return sushiPlatLinux;
  if (Platform.isMacOS) return sushiPlatMacOS;
  if (Platform.isIOS) return sushiPlatIOS;
  if (!Platform.isAndroid) return '';

  final info = await DeviceInfoPlugin().androidInfo;
  if (info.systemFeatures.contains('android.software.leanback')) {
    return sushiPlatAndroidTV;
  }
  if (info.supportedAbis.contains('arm64-v8a')) return sushiPlatAndroidNew;
  return sushiPlatAndroidOld;
}
