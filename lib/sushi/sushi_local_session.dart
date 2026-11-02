import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_delivery_reader_sync.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_login_kind_store.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_provider_bots_bootstrap.dart';
import 'package:fladder/sushi/sushi_taste_local.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_session_cache.dart';

/// Stamp tying the on-device catalog SQLite to one Sushi assignment.
abstract final class SushiCatalogOwnerStore {
  static const key = 'sushi.catalog.owner';

  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? '';
  }

  static Future<void> write(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    if (owner.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, owner);
  }
}

/// Binding token (or API-bot pool) of the current assignment. Empty when none is usable —
/// catalog must then refuse leftover rows from a previous Telegram identity.
Future<String> sushiCatalogSessionOwnerFromAssignment() async {
  final assignment = await SushiAssignmentStore.load();
  if (assignment == null || assignment.pending) return '';
  final token = assignment.bindingToken.trim();
  if (token.isNotEmpty) return token;
  final pool = assignment.apiSendTargets;
  if (pool.isEmpty) return '';
  return 'bots:${pool.join(',')}';
}

/// Drops every on-device Sushi artifact that belongs to the signed-in session.
///
/// Catalog SQLite, assignment, cached bot token, login kind, open requests, playback
/// warmup. Logout must await this — otherwise Play paints from the previous identity's
/// `/files` while `/play` has no assignment.
Future<void> sushiResetLocalSession({SushiCatalogController? catalog}) async {
  await SushiAssignmentStore.clear();
  await SushiCatalogOwnerStore.write('');
  await SushiLoginKindStore.clear();
  await SushiRequestedNotifier.clearPersisted();
  await sushiClearLocalTasteComplete();
  sushiResetInitbotColdStart();
  sushiPlayWarmup.clear();
  SushiTdlibSessionCache.clearAll();
  sushiClearPlaybackCacheOnAccountSwitch();
  SushiProviderBotsBootstrap.reset();
  await sushiClearPersistedLatestApp();
  await SushiTdlibBridgeController.instance().clearCachedBotToken();
  if (catalog != null) {
    await catalog.wipeSession();
  }
}
