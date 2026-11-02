import 'package:fladder/sushi/sushi_playback_link_cache.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart' show SushiTdlibAuthStateKind;

/// Outcome of aligning the native Telegram session with the signed-in account.
enum SushiReaderSyncResult {
  /// Native session is usable for delivery (or nothing to check).
  aligned,

  /// Could not determine which reader is required.
  unknown,

  /// A switch was required and failed.
  mismatched,
}

/// Confirms THIS device's native Telegram session is still a usable identity.
///
/// OX HTTP `/auth/bot-token` lookup removed (R-API-4). Without that lookup we only
/// treat mid phone-SMS / 2FA as [unknown]; otherwise [aligned].
Future<SushiReaderSyncResult> sushiEnsureTdlibMatchesUser(String? accessToken) async {
  final token = accessToken?.trim() ?? '';
  if (token.isEmpty) return SushiReaderSyncResult.aligned;

  final controller = SushiTdlibBridgeController.instance();

  if (controller.state.kind == SushiTdlibAuthStateKind.waitingForCode ||
      controller.state.kind == SushiTdlibAuthStateKind.waitingForPassword) {
    return SushiReaderSyncResult.unknown;
  }

  return SushiReaderSyncResult.aligned;
}

void sushiClearPlaybackCacheOnAccountSwitch() {
  SushiPlaybackLinkCache.clearAll();
}
