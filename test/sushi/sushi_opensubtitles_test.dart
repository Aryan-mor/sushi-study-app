import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/sushi_http.dart';
import 'package:fladder/sushi/subtitles/sushi_opensubtitles.dart';

void main() {
  test('pick first file_id from search JSON', () {
    final body = jsonEncode({
      'data': [
        {
          'attributes': {
            'download_count': 9,
            'files': [
              {'file_id': 4242, 'file_name': 'movie.en.srt'},
            ],
          },
        },
      ],
    });
    expect(sushiOpenSubtitlesPickFileId(body), 4242);
    expect(sushiOpenSubtitlesPickFileId('{"data":[]}'), isNull);
  });

  test('decode gzip SRT and strip BOM', () {
    final srt = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';
    final gz = Uint8List.fromList(GZipEncoder().encode(utf8.encode(srt)));
    expect(sushiOpenSubtitlesDecodeSrt(gz), contains('Hello'));
    expect(sushiOpenSubtitlesDecodeSrt(Uint8List.fromList(utf8.encode('\uFEFF$srt'))), contains('Hello'));
  });

  test('allowlist OpenSubtitles HTTPS hosts', () {
    expect(sushiHttpUriAllowed(Uri.parse('https://api.opensubtitles.com/api/v1/subtitles')), isTrue);
    expect(sushiHttpUriAllowed(Uri.parse('https://www.opensubtitles.com/download/x')), isTrue);
    expect(sushiHttpUriAllowed(Uri.parse('http://api.opensubtitles.com/x')), isFalse);
  });
}
