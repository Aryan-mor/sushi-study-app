import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/sushi/sushi_item_ratings.dart';
import 'package:fladder/sushi/sushi_api_disk_cache.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';

/// Cached SushiRatings for a library item detail page (keyed by catalog item id).
final sushiLibraryItemRatingsProvider = StateProvider.family<SushiItemRatings?, String>((ref, itemId) => null);

/// Reads `SushiRatings` from a Jellyfin item JSON payload.
SushiItemRatings? sushiRatingsFromItemJson(Map<String, dynamic> raw) {
  return sushiParseItemRatingsJson(raw['SushiRatings']);
}

void sushiApplyLibraryItemRatings(Ref ref, String itemId, SushiItemRatings? ratings) {
  if (!SushiEnv.isEnabled) return;
  ref.read(sushiLibraryItemRatingsProvider(itemId).notifier).state = ratings;
}

/// Fetches `GET /Items/{id}` and returns the raw JSON (includes `SushiRatings` when present).
Future<Map<String, dynamic>?> sushiFetchLibraryItemJson(Ref ref, String itemId) async {
  if (!SushiEnv.isEnabled) return null;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (baseUrl == null || baseUrl.isEmpty || token.isEmpty || itemId.isEmpty) {
    return null;
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: userId != null ? {'userId': userId} : null,
  );

  try {
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'MediaBrowser Token="$token"',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;

    final cacheUserId = userId ?? '';
    if (cacheUserId.isNotEmpty && response.body.isNotEmpty) {
      await SushiApiDiskCache.write(
        SushiApiDiskCache.key(userId: cacheUserId, method: 'GET', uri: uri),
        SushiApiDiskCacheEntry(
          savedAt: DateTime.now().toUtc(),
          statusCode: response.statusCode,
          body: response.body,
          headers: {'content-type': response.headers['content-type'] ?? 'application/json'},
        ),
      );
    }

    return body;
  } catch (_) {
    return null;
  }
}

Future<ItemBaseModel?> sushiFetchFreshItemForPlayback(Ref ref, String itemId) async {
  if (!SushiEnv.isEnabled || itemId.isEmpty) return null;
  final raw = await sushiFetchLibraryItemJson(ref, itemId);
  if (raw == null) return null;
  try {
    final dto = BaseItemDto.fromJsonFactory(raw);
    return ItemBaseModel.fromBaseDto(dto, ref);
  } catch (_) {
    return null;
  }
}

Future<void> sushiPatchLibraryItemPlaybackInCache(
  Ref ref,
  String itemId,
  Duration position,
) async {
  if (!SushiEnv.isEnabled || itemId.isEmpty) return;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  if (baseUrl == null || baseUrl.isEmpty || userId == null || userId.isEmpty) return;

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: {'userId': userId},
  );
  final cacheKey = SushiApiDiskCache.key(userId: userId, method: 'GET', uri: uri);
  final entry = await SushiApiDiskCache.read(cacheKey);
  if (entry == null || entry.body.isEmpty) return;

  try {
    final decoded = jsonDecode(entry.body);
    if (decoded is! Map<String, dynamic>) return;

    final runTimeTicks = decoded['RunTimeTicks'];
    final runTime = runTimeTicks is num && runTimeTicks > 0
        ? Duration(milliseconds: (runTimeTicks / 10000).round())
        : Duration.zero;
    final existing = decoded['UserData'];
    final current = existing is Map<String, dynamic>
        ? UserData(
            isFavourite: existing['IsFavorite'] == true,
            playCount: existing['PlayCount'] is num ? (existing['PlayCount'] as num).toInt() : 0,
            playbackPositionTicks:
                existing['PlaybackPositionTicks'] is num ? (existing['PlaybackPositionTicks'] as num).toInt() : 0,
            progress: existing['PlayedPercentage'] is num ? (existing['PlayedPercentage'] as num).toDouble() : 0,
            played: existing['Played'] == true,
          )
        : const UserData();
    final next = sushiDerivePlaybackUserData(
      current: current,
      position: position,
      runTime: runTime,
    );
    decoded['UserData'] = {
      if (existing is Map<String, dynamic>) ...existing,
      'PlaybackPositionTicks': next.playbackPositionTicks,
      'PlayedPercentage': next.progress,
      'Played': next.played,
      'PlayCount': next.playCount,
      if (next.lastPlayed != null) 'LastPlayedDate': next.lastPlayed!.toUtc().toIso8601String(),
    };

    await SushiApiDiskCache.write(
      cacheKey,
      SushiApiDiskCacheEntry(
        savedAt: DateTime.now().toUtc(),
        statusCode: entry.statusCode,
        body: jsonEncode(decoded),
        headers: entry.headers,
      ),
    );
  } catch (_) {}
}

Future<Map<String, dynamic>?> sushiLoadCachedLibraryItemJson(Ref ref, String itemId) async {
  if (!SushiEnv.isEnabled || itemId.isEmpty) return null;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  if (baseUrl == null || baseUrl.isEmpty || userId == null || userId.isEmpty) {
    return null;
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: {'userId': userId},
  );
  final entry = await SushiApiDiskCache.read(
    SushiApiDiskCache.key(userId: userId, method: 'GET', uri: uri),
  );
  if (entry == null || entry.body.isEmpty) return null;
  try {
    final body = jsonDecode(entry.body);
    return body is Map<String, dynamic> ? body : null;
  } catch (_) {
    return null;
  }
}

Future<({ItemBaseModel model, SushiItemRatings? ratings})?> sushiFetchLibraryItemDetails(
  Ref ref,
  String itemId,
) async {
  final raw = await sushiFetchLibraryItemJson(ref, itemId);
  if (raw == null) return null;

  final dto = BaseItemDto.fromJsonFactory(raw);
  final model = ItemBaseModel.fromBaseDto(dto, ref);
  final ratings = sushiRatingsFromItemJson(raw);
  sushiApplyLibraryItemRatings(ref, itemId, ratings);
  return (model: model, ratings: ratings);
}

Future<({ItemBaseModel model, SushiItemRatings? ratings})?> sushiLoadCachedLibraryItemDetails(
  Ref ref,
  String itemId,
) async {
  final raw = await sushiLoadCachedLibraryItemJson(ref, itemId);
  if (raw == null) return null;

  try {
    final dto = BaseItemDto.fromJsonFactory(raw);
    final model = ItemBaseModel.fromBaseDto(dto, ref);
    final ratings = sushiRatingsFromItemJson(raw);
    sushiApplyLibraryItemRatings(ref, itemId, ratings);
    return (model: model, ratings: ratings);
  } catch (_) {
    return null;
  }
}

/// Rotten Tomatoes / IMDb badges for library detail headers.
List<SimpleLabel> sushiSeerrRatingLabels(BuildContext context, SushiItemRatings? ratings) {
  if (ratings == null) return const [];

  final labels = <SimpleLabel>[];

  if (ratings.rtCritics != null) {
    labels.add(
      SimpleLabel(
        label: Text('${ratings.rtCritics}%'),
        iconWidget: SvgPicture.asset(
          'icons/tomato.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        iconColor: Colors.white,
        color: Colors.redAccent.shade700,
      ),
    );
    if (ratings.rtAudience != null) {
      labels.add(
        SimpleLabel(
          label: Text('${ratings.rtAudience}%'),
          iconWidget: SvgPicture.asset(
            'icons/popcorn_bucket.svg',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          iconColor: Colors.white,
          color: Colors.orange.shade700,
        ),
      );
    }
  }

  final imdbScore = ratings.imdbScore;
  if (imdbScore != null) {
    labels.add(
      SimpleLabel(
        label: Text(imdbScore.toStringAsFixed(1)),
        icon: Icons.star_rounded,
        iconColor: Colors.black,
        color: Colors.amber.shade600,
      ),
    );
  }

  return labels;
}
