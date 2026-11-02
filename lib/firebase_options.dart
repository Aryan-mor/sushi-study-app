// Stripped for Sushi — no Firebase project. Crashlytics init is skipped via SushiConfig.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions? _resolvedAndroid;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('DefaultFirebaseOptions have not been configured for web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final cached = _resolvedAndroid;
        if (cached != null) return cached;
        throw UnsupportedError(
          'Android FirebaseOptions not resolved — call ensureAndroidResolved() first.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static Future<FirebaseOptions> ensureAndroidResolved() async {
    if (_resolvedAndroid != null) return _resolvedAndroid!;
    await PackageInfo.fromPlatform();
    _resolvedAndroid = android;
    return _resolvedAndroid!;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'disabled',
    appId: '1:0:android:0',
    messagingSenderId: '0',
    projectId: 'disabled',
    storageBucket: 'disabled.appspot.com',
  );

  static const FirebaseOptions androidDev = android;
}
