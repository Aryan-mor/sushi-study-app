import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:fladder/sushi/sushi_delivery_reader_sync.dart';
import 'package:fladder/sushi/sushi_provider_bots_bootstrap.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';

/// Clears the on-device Telegram (gotd) session when the user signs out of OX.
/// OX [authProvider.logOutUser] alone leaves AuthReady — QR then fails with
/// `Cannot start QR login from state=ready`.
///
/// Catalog / assignment reset is [sushiResetLocalSession] — await that on the logout
/// path before this. Native logOut can stay unawaited so the login screen is not
/// blocked ~30s.
Future<void> sushiLogoutTelegramSession() async {
  SushiProviderBotsBootstrap.reset();
  sushiClearPlaybackCacheOnAccountSwitch();
  try {
    await SushiTdlibBridgeController.instance().clearSessionAfterSushiLogout();
  } catch (e, st) {
    developer.log(
      'Telegram logout after OX sign-out failed: $e',
      name: 'sushi-tdlib-auth',
      stackTrace: st,
    );
    if (kDebugMode) {
      debugPrint('[sushi-tdlib-auth] Telegram logout after OX sign-out failed: $e');
    }
  }
}
