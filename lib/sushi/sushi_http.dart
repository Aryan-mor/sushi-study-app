import 'package:fladder/sushi/sushi_config.dart';

/// Neutral UA — must not name Sushi (doc 07 §8).
const kSushiHttpUserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36';

/// R-SEC-12 / ADR 0013: posters on TMDB, bot-login preview on t.me.
///
/// Temporary exceptions (doc 15 §11/§12, until slices 2–5 + a server translate path exist):
/// sub-plus.ir (keyless Persian subtitle API; ZIP may be plain HTTP),
/// generativelanguage.googleapis.com (user-owned Gemini key, not ours),
/// and OpenSubtitles.com (anonymous 5 downloads/day English fallback for AI translate).
///
/// www.youtube-nocookie.com (ADR 0031): the in-app trailer player's WebView navigates here only,
/// never www.youtube.com -- the privacy-enhanced embed domain, same host apps commonly use to
/// avoid YouTube's tracking cookies on a page the viewer never asked to visit YouTube itself for.
bool sushiHttpUriAllowed(Uri uri) {
  final host = uri.host.toLowerCase();
  if (host == 'sub-plus.ir') {
    return uri.scheme == 'https' || uri.scheme == 'http';
  }
  if (uri.scheme != 'https') return false;
  if (host == 'image.tmdb.org') return true;
  if (host == 'www.youtube-nocookie.com') return true;
  if (host == 'generativelanguage.googleapis.com') return true;
  if (_openSubtitlesHost(host)) return true;
  if (uri.host == 't.me' && uri.path == '/s/${SushiConfig.loginChannelUsername}') {
    return true;
  }
  return false;
}

bool _openSubtitlesHost(String host) {
  return host == 'opensubtitles.com' ||
      host.endsWith('.opensubtitles.com') ||
      host == 'opensubtitles.org' ||
      host.endsWith('.opensubtitles.org');
}

/// Throws [StateError] when [uri] is off the allowlist.
void sushiHttpAssertAllowed(Uri uri) {
  if (!sushiHttpUriAllowed(uri)) {
    throw StateError('http host is not on the allowlist: ${uri.host}');
  }
}
