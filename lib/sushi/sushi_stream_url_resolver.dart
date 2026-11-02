import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/sushi/sushi_provider_read.dart';
import 'package:fladder/sushi/sushi_stream_log.dart';
import 'package:fladder/sushi/sushi_tdlib_playback_resolver.dart';
import 'package:fladder/sushi/sushi_tdlib_session_cache.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';

/// Resolves a PlaybackInfo-minted URL to a playable one. Telegram-native links resolve via the
/// device's own TDLib session; any other URL (e.g. the store-review test account's direct demo
/// clip) is returned unchanged — there's no CDN/proxy layer left to rewrite it through.
Future<String?> sushiResolveStreamPlaybackUrl(
  SushiRead read,
  String? apiMintedUrl, {
  bool forceRefreshNodes = false,
}) async {
  if (!sushiIsTelegramProviderLink(apiMintedUrl)) {
    return apiMintedUrl;
  }

  final wantedPlayer = read(videoPlayerSettingsProvider).wantedPlayer;
  // TEMP (Windows bridge parity test): prefer HTTP bridge + libmpv on all platforms,
  // including Android. Product default was Android → tdlib-file:// + Exo; restore later
  // by gating Android to preferHttpBridge=false again. gotd-only either way.
  final useHttpBridge = wantedPlayer != PlayerOptions.nativePlayer;
  final telegramUrl = apiMintedUrl!;

  if (forceRefreshNodes) {
    SushiTdlibSessionCache.invalidateTelegramUrl(telegramUrl);
  }

  final sw = Stopwatch()..start();
  final cached = SushiTdlibSessionCache.get(telegramUrl, preferHttpBridge: useHttpBridge);
  if (cached != null && !forceRefreshNodes) {
    SushiStreamLog.event('tdlib_cache_hit', fields: {
      'url': SushiStreamLog.describeUrl(telegramUrl),
      'resolved': SushiStreamLog.describeUrl(cached),
    });
    return cached;
  }

  final resolved = await SushiTdlibSessionCache.resolveOrStart(
    telegramUrl,
    preferHttpBridge: useHttpBridge,
    start: () => sushiResolveTdlibPlaybackUrl(
      telegramUrl,
      preferHttpBridge: useHttpBridge,
    ),
  );
  SushiStreamLog.event('tdlib_resolve', fields: {
    'url': SushiStreamLog.describeUrl(telegramUrl),
    'resolved': SushiStreamLog.describeUrl(resolved),
    'tdlibResolveMs': sw.elapsedMilliseconds,
    'cacheHit': false,
  });
  return resolved;
}
