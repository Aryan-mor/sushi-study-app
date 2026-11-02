import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_tdlib_playback_resolver.dart';

/// Progressive byte-range sources that must not get MPV's short reopen-retry loop.
/// Telegram direct-play (gotd) via either transport — loopback HTTP bridge or (Windows) stream_cb.
bool sushiStreamProgressiveHttpUrl(String url) {
  if (!SushiEnv.isEnabled) return false;
  return sushiIsTelegramDirectPlayUrl(url);
}

/// Large client-side resume/seek on progressive HTTP needs long MPV load grace.
bool sushiStreamMpvResumeSeekGrace(String url, Duration startPosition) {
  return sushiStreamProgressiveHttpUrl(url) &&
      startPosition > const Duration(seconds: 30);
}

/// MPV must not reopen the HTTP read while ExoPlayer/mpv is still seeking.
const sushiStreamMpvResumeRetryInterval = Duration(seconds: 90);

/// Upper bound before MPV gives up and runs force-repair.
const sushiStreamMpvResumeMaxRetry = Duration(minutes: 4);

/// Fallback [onReady] when duration stays 0 during resume seek.
const sushiStreamMpvResumeReadyTimeout = Duration(seconds: 90);

/// Default progressive-playback ready timeout.
const sushiStreamMpvDefaultReadyTimeout = Duration(seconds: 12);

/// Post-open resume seeks on gotdstream: first attempt is rejected until mpv
/// builds the container index. Keep retrying a bit longer than 3×700ms — a
/// 68-minute resume also has to wait out Telegram FLOOD_WAIT on the cue range.
const sushiStreamMpvResumeSeekAttempts = 8;
const sushiStreamMpvResumeSeekRetryDelay = Duration(seconds: 1);
