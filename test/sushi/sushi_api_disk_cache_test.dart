import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/sushi/sushi_api_disk_cache.dart';
import 'package:fladder/sushi/sushi_swr_http_client.dart';

void main() {
  test('SushiApiDiskCache.key is stable and user-scoped', () {
    final uri = Uri.parse('https://api.example/Users/u1/Home/Feed?limit=16');
    final a = SushiApiDiskCache.key(userId: 'u1', method: 'GET', uri: uri);
    final b = SushiApiDiskCache.key(userId: 'u1', method: 'get', uri: uri);
    final c = SushiApiDiskCache.key(userId: 'u2', method: 'GET', uri: uri);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 16);
  });

  test('sushiSwrShouldCacheRequest allowlist skips playback and auth', () {
    expect(
      sushiSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Users/1/Views'))),
      isTrue,
    );
    expect(
      sushiSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Shows/abc/Seasons'))),
      isTrue,
    );
    expect(
      sushiSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Shows/abc/Episodes'))),
      isTrue,
    );
    expect(
      sushiSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Items/abc/PlaybackInfo'))),
      isFalse,
    );
    expect(
      sushiSwrShouldCacheRequest(http.Request('POST', Uri.parse('https://x/Items'))),
      isFalse,
    );
  });
}
