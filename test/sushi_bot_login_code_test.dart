import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_bot_login_code.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_http.dart';
import 'package:fladder/sushi/sushi_login_channel.dart';
import 'package:fladder/sushi/sushi_login_seal.dart';

void main() {
  const token = '123456789:AAFq7v9dR3n8xyzABCDEFGHIJKLMNOPQRSTU';

  test('looks like a bot token', () {
    expect(sushiLooksLikeBotToken(token), isTrue);
    expect(sushiLooksLikeBotToken('hello'), isFalse);
  });

  test('seal/open round-trip', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    final blob = await sushiSealLoginToken(token, nonce);
    expect(blob, startsWith('s2.'));
    expect(await sushiOpenLoginBlob(blob, nonce), token);
  });

  test('open rejects the wrong nonce', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    final other = Uint8List.fromList(List<int>.filled(16, 0x22));
    final blob = await sushiSealLoginToken(token, nonce);
    expect(await sushiOpenLoginBlob(blob, other), isNull);
  });

  test('deterministic golden matches Go SealWithGCMNonce', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    final iv = Uint8List.fromList(List<int>.filled(12, 0x22));
    final blob = await sushiSealLoginToken(token, nonce, gcmNonce: iv);
    expect(await sushiOpenLoginBlob(blob, nonce), token);
    expect(
      blob,
      's2.IiIiIiIiIiIiIiIic7rSDpwEKm0TXggheiOCuucA8xMDFo17Clw5k9I9tFnFkZmcrV5ZWVDpSEfDTmWonEu1xgKR3y1YqKCDd9k',
    );
  });

  test('search tag is deterministic and hex', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    final tagA = await sushiLoginSearchTag(nonce);
    expect(tagA, hasLength(10));
    expect(RegExp(r'^[0-9a-f]{10}$').hasMatch(tagA), isTrue);
    expect(await sushiLoginSearchTag(nonce), tagA, reason: 'must be deterministic');

    final other = Uint8List.fromList(List<int>.filled(16, 0x22));
    expect(await sushiLoginSearchTag(other), isNot(tagA));
  });

  test('search tag golden matches Go botlogin.SearchTag', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    // Keep in sync with TestSearchTagMatchesDart in botlogin_test.go.
    expect(await sushiLoginSearchTag(nonce), '0eb1feafa2');
  });

  test('search uri is the login channel path with a #tag query, hashtag-encoded', () {
    final uri = sushiLoginChannelSearchUri('0eb1feafa2');
    expect(uri.host, 't.me');
    expect(uri.path, '/s/${SushiConfig.loginChannelUsername}');
    expect(uri.query, 'q=%230eb1feafa2');
    expect(sushiHttpUriAllowed(uri), isTrue,
        reason: 'query string must not fall off the path allowlist');
  });

  test('extract blobs from t.me/s html', () async {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x05));
    final blob = await sushiSealLoginToken(token, nonce);
    final html =
        '<div class="tgme_widget_message_text">test</div>'
        '<div class="tgme_widget_message_text">$blob</div>';
    expect(sushiExtractLoginBlobs(html), [blob]);
  });

  test('start payload is ac_ + 16-byte nonce', () {
    final nonce = Uint8List.fromList(List<int>.filled(16, 0x11));
    final payload = sushiLoginStartPayload(nonce);
    expect(payload, startsWith('ac_'));
    expect(payload.length, lessThan(64));
  });

  test('http allowlist', () {
    expect(
        sushiHttpUriAllowed(Uri.parse('https://image.tmdb.org/t/p/w500/x.jpg')),
        isTrue);
    expect(
        sushiHttpUriAllowed(Uri.parse(
            'https://t.me/s/${SushiConfig.loginChannelUsername}')),
        isTrue);
    expect(sushiHttpUriAllowed(Uri.parse('https://t.me/s/other')), isFalse);
    expect(sushiHttpUriAllowed(Uri.parse('https://example.com/')), isFalse);
    expect(sushiHttpUriAllowed(Uri.parse('http://t.me/s/exampleLoginChannel')),
        isFalse);
    expect(sushiHttpUriAllowed(Uri.parse('https://sub-plus.ir/api.php')), isTrue);
    expect(sushiHttpUriAllowed(Uri.parse('http://sub-plus.ir/download/x.zip')),
        isTrue);
    expect(
        sushiHttpUriAllowed(Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/x')),
        isTrue);
    expect(sushiHttpUriAllowed(Uri.parse('http://image.tmdb.org/x')), isFalse);
    expect(
        sushiHttpUriAllowed(
            Uri.parse('https://api.opensubtitles.com/api/v1/subtitles')),
        isTrue);
  });
}
