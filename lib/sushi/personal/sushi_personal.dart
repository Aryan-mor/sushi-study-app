import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/sushi/personal/sushi_personal_thumbs.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_playback_resolver.dart';

/// Personal videos (ADR 0037): videos a person sent to main-bot, shown only in My videos (side
/// menu), never on Home. Played through the same delivery as a film, under `personal_id`.

const _personalItemIdPrefix = 'sushi_pv_';

String sushiPersonalItemId(int personalId) => '$_personalItemIdPrefix$personalId';

/// The personal video id behind an item id built by [sushiPersonalItemId], or null.
int? sushiPersonalIdFromItemId(String itemId) {
  if (!itemId.startsWith(_personalItemIdPrefix)) return null;
  return int.tryParse(itemId.substring(_personalItemIdPrefix.length));
}

/// A card as a [MovieModel], so Fladder's player, progress bar and play helper take it as is.
MovieModel sushiPersonalVideoToItem(SushiPersonalVideo v) {
  final runTime = v.durationS > 0 ? Duration(seconds: v.durationS) : null;
  final progress = (v.durationS > 0 && !v.done) ? (v.positionS * 100 / v.durationS).clamp(0, 100).toDouble() : 0.0;
  return MovieModel(
    name: v.title,
    id: sushiPersonalItemId(v.personalId),
    images: null,
    originalTitle: v.title,
    // Required by the model; a personal video has no release date and the card never shows one.
    premiereDate: DateTime.now(),
    sortName: v.title,
    status: '',
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: const []),
    overview: OverviewModel(runTime: runTime),
    parentId: null,
    playlistId: null,
    childCount: null,
    primaryRatio: 16 / 9,
    userData: UserData(
      played: v.done,
      progress: progress,
      playbackPositionTicks: v.done ? 0 : v.positionS * 10000000,
    ),
    canDelete: false,
    canDownload: false,
    jellyType: BaseItemKind.movie,
  );
}

/// The playback model for a personal video: `/play` with `personal_id`, no catalog lookups, no
/// queue. Null when the resolve fails, like [sushiBuildPlaybackModel].
Future<SushiPlaybackModel?> sushiBuildPersonalPlaybackModel(
  ItemBaseModel item, {
  required int personalId,
  bool preferHttpBridge = false,
}) async {
  try {
    final url = await sushiResolvePlaybackUrl(
      fileId: 0,
      personalId: personalId,
      preferHttpBridge: preferHttpBridge,
    );
    return SushiPlaybackModel(item: item, media: Media(url: url), personalId: personalId);
  } catch (e, st) {
    debugPrint('[sushi] personal play resolve failed: $e\n$st');
    return null;
  }
}

/// My videos, as last known.
class SushiMyVideosState {
  const SushiMyVideosState({this.videos = const [], this.loading = false, this.loaded = false, this.failed = false});

  final List<SushiPersonalVideo> videos;

  /// A refresh is in flight.
  final bool loading;

  /// At least one answer (cached or fresh) has been shown — before that, an empty list means
  /// "not known yet", not "you have none".
  final bool loaded;

  /// The last refresh failed; [videos] is whatever was known before.
  final bool failed;

  SushiMyVideosState copyWith({List<SushiPersonalVideo>? videos, bool? loading, bool? loaded, bool? failed}) =>
      SushiMyVideosState(
        videos: videos ?? this.videos,
        loading: loading ?? this.loading,
        loaded: loaded ?? this.loaded,
        failed: failed ?? this.failed,
      );
}

/// Renders the local copy first, then replaces it with the server's answer (docs/07 §10).
class SushiMyVideosNotifier extends StateNotifier<SushiMyVideosState> {
  SushiMyVideosNotifier() : super(const SushiMyVideosState());

  /// Upper bound on pages walked per refresh; one person's list is small (upload quota).
  static const _maxPages = 20;

  Future<void> refresh() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, failed: false);
    final scope = await _cacheScope();
    if (!state.loaded && scope != null) {
      final cached = await _readCache(scope);
      if (cached != null && mounted) state = state.copyWith(videos: cached, loaded: true);
    }

    final fresh = await _fetchAll();
    if (!mounted) return;
    if (fresh == null) {
      state = state.copyWith(loading: false, failed: true);
      return;
    }
    state = SushiMyVideosState(videos: fresh, loaded: true);
    if (scope != null) await _writeCache(scope, fresh);
    await sushiPrunePersonalThumbs({for (final v in fresh) v.personalId});
  }

  /// Drops a card at once after a delete (ADR 0038); the server's list agrees after replication.
  Future<void> removeLocal(int personalId) async {
    final videos = [
      for (final v in state.videos)
        if (v.personalId != personalId) v
    ];
    state = state.copyWith(videos: videos);
    final scope = await _cacheScope();
    if (scope != null) await _writeCache(scope, videos);
    await sushiPrunePersonalThumbs({for (final v in videos) v.personalId});
  }

  Future<List<SushiPersonalVideo>?> _fetchAll() async {
    final out = <SushiPersonalVideo>[];
    var cursor = 0;
    for (var page = 0; page < _maxPages; page++) {
      final res = await sushiFetchList(scope: SushiListScope.myVideos, cursor: cursor);
      if (res == null) return page == 0 ? null : out;
      out.addAll(res.personalVideos);
      if (res.cursor == 0) break;
      cursor = res.cursor;
    }
    return out;
  }
}

final sushiMyVideosProvider =
    StateNotifierProvider<SushiMyVideosNotifier, SushiMyVideosState>((ref) => SushiMyVideosNotifier());

// --- local copy, scoped to the binding so another account on this device never sees it ---

Future<String?> _cacheScope() async {
  final assignment = await SushiAssignmentStore.load();
  final token = assignment?.bindingToken ?? '';
  if (token.isEmpty) return null;
  var h = 0x811c9dc5;
  for (final b in utf8.encode(token)) {
    h = ((h ^ b) * 16777619) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

Future<File?> _cacheFile(String scope) async {
  if (kIsWeb) return null;
  try {
    final root = await getApplicationSupportDirectory();
    return File('${root.path}${Platform.pathSeparator}sushi_my_videos_$scope.json');
  } catch (_) {
    return null;
  }
}

Future<List<SushiPersonalVideo>?> _readCache(String scope) async {
  final file = await _cacheFile(scope);
  if (file == null || !await file.exists()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return null;
    return [
      for (final e in decoded)
        if (e is Map<String, dynamic>)
          SushiPersonalVideo(
            personalId: (e['id'] as num?)?.toInt() ?? 0,
            title: e['title'] as String? ?? '',
            durationS: (e['duration'] as num?)?.toInt() ?? 0,
            sizeBytes: (e['size'] as num?)?.toInt() ?? 0,
            positionS: (e['position'] as num?)?.toInt() ?? 0,
            done: e['done'] == true,
          ),
    ];
  } catch (e) {
    debugPrint('[sushi] my videos cache read: $e');
    return null;
  }
}

Future<void> _writeCache(String scope, List<SushiPersonalVideo> videos) async {
  final file = await _cacheFile(scope);
  if (file == null) return;
  try {
    await file.writeAsString(jsonEncode([
      for (final v in videos)
        {
          'id': v.personalId,
          'title': v.title,
          'duration': v.durationS,
          'size': v.sizeBytes,
          'position': v.positionS,
          'done': v.done,
        },
    ]));
  } catch (e) {
    debugPrint('[sushi] my videos cache write: $e');
  }
}
