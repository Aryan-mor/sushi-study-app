import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_http.dart';

const _apiRoot = 'https://api.opensubtitles.com/api/v1';
const _timeout = Duration(seconds: 20);
/// OpenSubtitles rejects a generic browser UA. Must match the registered consumer name.
const kOpenSubtitlesUserAgent = 'SushiApp v1.1';

class SushiOpenSubtitlesException implements Exception {
  SushiOpenSubtitlesException(this.message);
  final String message;
  @override
  String toString() => 'SushiOpenSubtitlesException: $message';
}

/// Anonymous OpenSubtitles.com REST client (doc 15 §12). No user login — 5 downloads / IP / day
/// with a free app consumer key.
class SushiOpenSubtitlesClient {
  SushiOpenSubtitlesClient({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _apiKey = (apiKey ?? SushiConfig.openSubtitlesApiKey).trim();

  final http.Client _client;
  final String _apiKey;

  bool get configured => _apiKey.isNotEmpty;

  Future<String?> fetchEnglishSrt({
    required String title,
    int? tmdbId,
    ({int season, int episode})? episode,
    String? year,
  }) async {
    if (!configured) return null;
    final fileId = await _searchFileId(
      title: title,
      tmdbId: tmdbId,
      episode: episode,
      year: year,
    );
    if (fileId == null) return null;
    return _downloadSrt(fileId);
  }

  Future<int?> _searchFileId({
    required String title,
    int? tmdbId,
    ({int season, int episode})? episode,
    String? year,
  }) async {
    final params = <String, String>{
      'languages': 'en',
      'order_by': 'download_count',
      'order_direction': 'desc',
    };
    if (episode != null) {
      params['type'] = 'episode';
      params['season_number'] = '${episode.season}';
      params['episode_number'] = '${episode.episode}';
    } else {
      params['type'] = 'movie';
    }
    if (tmdbId != null && tmdbId > 0) {
      if (episode != null) {
        params['parent_tmdb_id'] = '$tmdbId';
      } else {
        params['tmdb_id'] = '$tmdbId';
      }
    }
    params['query'] = title;
    if (year != null && year.isNotEmpty) params['year'] = year;
    final uri = Uri.parse('$_apiRoot/subtitles').replace(queryParameters: params);
    sushiHttpAssertAllowed(uri);
    final resp = await _client.get(uri, headers: _headers()).timeout(_timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    return sushiOpenSubtitlesPickFileId(resp.body);
  }

  Future<String?> _downloadSrt(int fileId) async {
    final uri = Uri.parse('$_apiRoot/download');
    sushiHttpAssertAllowed(uri);
    final resp = await _client
        .post(
          uri,
          headers: {
            ..._headers(),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'file_id': fileId}),
        )
        .timeout(_timeout);
    if (resp.statusCode == 406 || resp.statusCode == 429) {
      throw SushiOpenSubtitlesException('daily download limit');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final link = (decoded['link'] as String?)?.trim() ?? '';
    if (link.isEmpty) return null;
    final fileUri = Uri.parse(link);
    sushiHttpAssertAllowed(fileUri);
    final file = await _client.get(fileUri, headers: _headers()).timeout(const Duration(seconds: 45));
    if (file.statusCode != 200 || file.bodyBytes.isEmpty) return null;
    return sushiOpenSubtitlesDecodeSrt(file.bodyBytes);
  }

  Map<String, String> _headers() => {
        'Api-Key': _apiKey,
        'User-Agent': kOpenSubtitlesUserAgent,
        'Accept': 'application/json',
      };

  void close() => _client.close();
}

/// First `file_id` in a search payload. Public for tests.
int? sushiOpenSubtitlesPickFileId(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) return null;
  final data = decoded['data'];
  if (data is! List) return null;
  for (final row in data) {
    if (row is! Map) continue;
    final attrs = row['attributes'];
    if (attrs is! Map) continue;
    final files = attrs['files'];
    if (files is! List || files.isEmpty) continue;
    final first = files.first;
    if (first is! Map) continue;
    final id = first['file_id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
  }
  return null;
}

String sushiOpenSubtitlesDecodeSrt(Uint8List bytes) {
  var raw = bytes;
  if (raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
    raw = Uint8List.fromList(GZipDecoder().decodeBytes(raw));
  }
  var text = utf8.decode(raw, allowMalformed: true);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return text.trim();
}
