import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/sushi/sushi_auth_file_service.dart';
import 'package:fladder/sushi/sushi_desktop_deep_link.dart';
import 'package:fladder/sushi/sushi_dotenv.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_transport.dart';
import 'package:fladder/sushi/sushi_playback_details_refresh.dart';
import 'package:fladder/sushi/sushi_share_deep_link.dart';
import 'package:fladder/util/custom_cache_manager.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:protocol_handler/protocol_handler.dart';

/// Sushi startup hooks — keep upstream `main.dart` thin.
abstract final class SushiBootstrap {
  static Future<void> beforeAppBootstrap(List<String> args) async {
    await SushiDotenv.ensureLoaded();
    if (!kIsWeb && Platform.isWindows) {
      sushiRememberWindowsStartupArgs(args);
      await protocolHandler.register(kSushiDeepLinkScheme);
    }
    CustomCacheManager.instance = CacheManager(
      Config(
        CustomCacheManager.key,
        stalePeriod: const Duration(days: 7),
        maxNrOfCacheObjects: 512,
        fileService: SushiAuthFileService(),
      ),
    );
  }

  static Future<void> afterAppBootstrap(AppBootstrapResult result) async {
    if (kIsWeb) return;
    // ADR 0019: version arrives on HomeRes. No GitHub / Play checks.
    sushiBindUpdatePrompt(result.sharedPreferences, result.applicationInfo.version);
    sushiBindLatestAppRefresher(() async {
      await sushiFetchHome(tab: sushiHomeTabMovies);
    });
  }

  /// Wraps the app root so deferred update prompts can obtain a [BuildContext].
  static Widget wrapRoot(Widget child) {
    if (kIsWeb) return child;

    return SushiPlaybackDetailsRefresh(
      child: SushiShareDeepLinkHost(
        child: SushiUpdatePromptHost(child: child),
      ),
    );
  }
}
