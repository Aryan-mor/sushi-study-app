import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_http.dart';
import 'package:fladder/sushi/sushi_login_seal.dart';
import 'package:http/http.dart' as http;

/// Public preview the app polls while focused (ADR 0013).
Uri sushiLoginChannelUri() =>
    Uri.https('t.me', '/s/${SushiConfig.loginChannelUsername}');

/// Same preview, filtered to this login's `#<tag>` (ADR 0029). Telegram's own search on
/// `t.me/s/` is not limited to the visible ~20-message tail, so this finds a post that a slow
/// scan would otherwise miss because newer posts pushed it off that tail first.
Uri sushiLoginChannelSearchUri(String tag) =>
    Uri.https('t.me', '/s/${SushiConfig.loginChannelUsername}', {'q': '#$tag'});

/// GET the tag-filtered preview first, then fall back to the unfiltered one (Telegram's search
/// index can lag right after init-bot posts). Try to open each `s2.` blob found with [nonce].
Future<String?> sushiPollLoginChannel(http.Client client, List<int> nonce) async {
  final tag = await sushiLoginSearchTag(nonce);
  final token = await _pollLoginChannelAt(client, nonce, sushiLoginChannelSearchUri(tag));
  if (token != null) return token;
  return _pollLoginChannelAt(client, nonce, sushiLoginChannelUri());
}

Future<String?> _pollLoginChannelAt(http.Client client, List<int> nonce, Uri uri) async {
  if (!sushiHttpUriAllowed(uri)) {
    throw StateError('login channel host is not on the allowlist');
  }
  final res = await client.get(uri, headers: {'User-Agent': kSushiHttpUserAgent});
  if (res.statusCode != 200) return null;
  for (final blob in sushiExtractLoginBlobs(res.body)) {
    final token = await sushiOpenLoginBlob(blob, nonce);
    if (token != null) return token;
  }
  return null;
}
