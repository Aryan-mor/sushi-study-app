import 'package:flutter/foundation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/personal/sushi_personal.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_playback_resolver.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:fladder/sushi/sushi_movie_watch_state.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

/// Resolves the item's selected quality (docs/12 §5's pick-list, applied in
/// `sushi_item_adapter.dart`) to a playable [SushiPlaybackModel] via Sushi's own `/play` delivery
/// (docs/05) — entirely separate from Jellyfin's PlaybackInfo, which Sushi has none of.
///
/// Returns null when there's nothing to play (no file id picked yet, or the resolve failed) —
/// callers show the same "unable to play" state they already show for a null Sushi/Jellyfin
/// model.
///
/// Movies already carry `/files` on the model. Episodes fetch `/files` here if the pick-list is
/// still empty (user tapped a season/episode that was not the header play target).
/// Compact list rows have no files. Same `/item` + `/files` fetch the detail page does.
Future<ItemBaseModel> sushiHydrateForPlay(ItemBaseModel item, SushiCatalogController catalog) async {
  if (item is MovieModel) {
    if (sushiFileIdFromVersionStreamId(item.streamModel?.currentVersionStream?.id) != null) {
      return item;
    }
    final tmdbId = sushiTmdbIdFromItemId(item.id);
    if (tmdbId == null) return item;
    final snap = await catalog.openTitle(tmdbId: tmdbId, kind: SushiKind.movie);
    if (snap.page == null) return item;
    final localPreference = await sushiReadVariantPreference('movie:$tmdbId');
    return sushiEnrichMovieModel(
      item,
      snap.page!,
      snap.files,
      preferredFileId: snap.lastFileId,
      localPreference: localPreference,
    );
  }
  if (item is SeriesModel) {
    if (item.availableEpisodes?.isNotEmpty == true) return item;
    final tmdbId = sushiTmdbIdFromItemId(item.id);
    if (tmdbId == null) return item;
    final snap = await catalog.openTitle(tmdbId: tmdbId, kind: SushiKind.series);
    if (snap.page == null) return item;
    return sushiEnrichSeriesModel(item, snap.page!);
  }
  return item;
}

/// Ordered, playable sibling episodes for [episode]'s series — this is what drives the
/// player's next/previous-episode buttons (they read [PlaybackModel.nextVideo] /
/// [PlaybackModel.previousVideo], which walk the queue). Returns an empty list when the
/// series page can't be resolved from the catalog.
///
/// `/item` only carries the play-target episode (ADR 0028), so the player queue always
/// loads the current season via `/episodes`. At the first/last episode of a season it
/// also loads the adjacent season so next/prev can cross season boundaries.
Future<List<EpisodeModel>> sushiEpisodeQueueFor(
  EpisodeModel episode,
  SushiCatalogController catalog,
) async {
  final parentId = episode.parentId;
  if (parentId == null || parentId.isEmpty) return const [];
  final tmdbId = sushiTmdbIdFromItemId(parentId);
  if (tmdbId == null) return const [];
  final parent = episode.parentBaseModel;

  Future<List<EpisodeModel>> seasonQueue(int seasonNo) async {
    if (seasonNo < 1) return const [];
    final wire = await catalog.openSeason(
      tmdbId: tmdbId,
      kind: SushiKind.series,
      seasonNo: seasonNo,
    );
    return [
      for (final e in sushiEpisodesFromWire(parent, wire))
        if (e.playAble) e,
    ];
  }

  final current = await seasonQueue(episode.season);
  if (current.isEmpty) return const [];
  final adjacent = sushiEpisodeQueueAdjacentSeasons(currentSeason: current, playing: episode);
  final previous = adjacent.previous ? await seasonQueue(episode.season - 1) : const <EpisodeModel>[];
  final next = adjacent.next ? await seasonQueue(episode.season + 1) : const <EpisodeModel>[];
  return [...previous, ...current, ...next];
}

/// Extra seasons the player queue must fetch so next/prev work at a season edge.
({bool previous, bool next}) sushiEpisodeQueueAdjacentSeasons({
  required List<EpisodeModel> currentSeason,
  required EpisodeModel playing,
}) {
  var idx = currentSeason.indexWhere((e) => e.id == playing.id);
  if (idx < 0) {
    idx = currentSeason.indexWhere((e) => e.season == playing.season && e.episode == playing.episode);
  }
  return (
    previous: idx <= 0 && playing.season > 1,
    next: idx < 0 || idx >= currentSeason.length - 1,
  );
}

List<EpisodeModel> _playableEpisodes(Iterable<EpisodeModel>? episodes) => [
      for (final e in episodes ?? const <EpisodeModel>[])
        if (e.playAble) e,
    ];

SushiEpisode? _sushiEpisodeByNumber(List<SushiEpisode> episodes, int season, int episode) {
  for (final row in episodes) {
    if (row.seasonNo == season && row.episodeNo == episode && row.episodeId != 0) return row;
  }
  return null;
}

/// Map a continue-watching stub onto the catalog episode id.
///
/// The cached season list is the first look. A miss forces one `/episodes` so a
/// newly ingested episode (S1 E15 on a device that cached S1 E1–E14) plays that
/// file. Still missing means there is nothing to play — never a sibling's file.
Future<EpisodeModel?> sushiResolveStubEpisode(
  EpisodeModel stub,
  SushiCatalogController catalog,
) async {
  if (stub.season < 1 || stub.episode < 1) return null;
  final tmdbId = sushiTmdbIdFromItemId(stub.parentId ?? '');
  if (tmdbId == null) return null;

  Future<SushiEpisode?> lookup({required bool force}) async {
    final wire = await catalog.openSeason(
      tmdbId: tmdbId,
      kind: SushiKind.series,
      seasonNo: stub.season,
      force: force,
    );
    return _sushiEpisodeByNumber(wire, stub.season, stub.episode);
  }

  final match = await lookup(force: false) ?? await lookup(force: true);
  if (match == null) return null;
  return stub.copyWith(
    id: sushiEpisodeItemId(match.episodeId),
    mediaStreams: MediaStreamsModel(versionStreams: const []),
  );
}

Future<SeriesModel> _paintSeriesWatchState(
  SeriesModel series, {
  Set<String> playedIds = const {},
}) async {
  final tmdbId = sushiTmdbIdFromItemId(series.id);
  final resume = tmdbId == null
      ? null
      : await sushiContinueFind(tmdbId: tmdbId, kind: SushiKind.series);
  return sushiPaintSeriesWatchState(series, playedIds: playedIds, resume: resume);
}

Future<SushiPlaybackModel?> sushiBuildPlaybackModel(
  ItemBaseModel itemModel, {
  required SushiCatalogController catalog,
  bool preferHttpBridge = false,
  SyncNotifier? sync,
  Set<String> playedIds = const {},
}) async {
  // R-SCHED-3: play leaves home. Also keeps `/item` prefetch off the gomobile JNI
  // while HTTP ensureAvailable is in flight (bulkBarrierPreWrite, 2026-09-21).
  catalog.cancelPrefetch();
  // A personal video (ADR 0037) has no catalog row, files or queue: straight to `/play`.
  final personalId = sushiPersonalIdFromItemId(itemModel.id);
  if (personalId != null) {
    return sushiBuildPersonalPlaybackModel(itemModel, personalId: personalId, preferHttpBridge: preferHttpBridge);
  }
  var item = itemModel;
  if (item is SeriesModel ||
      (item is MovieModel &&
          sushiFileIdFromVersionStreamId(item.streamModel?.currentVersionStream?.id) == null)) {
    item = await sushiHydrateForPlay(item, catalog);
  }
  if (item is SeriesModel) {
    item = await _paintSeriesWatchState(item, playedIds: playedIds);
  }
  int? movieEpisodeId;
  if (item is MovieModel) {
    SushiFilesRes? files;
    final tmdbId = sushiTmdbIdFromItemId(item.id);
    if (tmdbId != null) {
      final snap = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.movie);
      files = snap?.filesRes;
      final eps = snap?.page?.episodes ?? const [];
      if (eps.isNotEmpty) movieEpisodeId = eps.first.episodeId;
    }
    item = await sushiLoadAndPaintMovieWatchState(item, playedIds: playedIds, files: files);
  }

  // Ordered sibling episodes for the queue. Captured here when we already hold the hydrated
  // series; the standalone-episode path fills it from the catalog further down.
  var episodeQueue = const <EpisodeModel>[];
  if (item is SeriesModel) {
    episodeQueue = _playableEpisodes(item.availableEpisodes);
    final episode = sushiSeriesDetailPlayTarget(item) ??
        (item.availableEpisodes == null || item.availableEpisodes!.isEmpty
            ? null
            : item.availableEpisodes!.first);
    if (episode == null) return null;
    item = episode;
  }

  if (item is EpisodeModel && sushiEpisodeIdFromItemId(item.id) == null) {
    // Continue-watching can sit past the cached season (`sushi_ep_stub_…_1_15`).
    // That id does not parse, so the block below would keep whatever file was
    // glued on — the series' first episode. Resolve the catalog row first.
    final resolved = await sushiResolveStubEpisode(item, catalog);
    if (resolved == null) return null;
    item = resolved;
  }

  MediaStreamsModel? streams = item.streamModel;
  var fileId = sushiFileIdFromVersionStreamId(streams?.currentVersionStream?.id);

  if (item is EpisodeModel) {
    final episodeId = sushiEpisodeIdFromItemId(item.id);
    if (episodeId == null) {
      if (fileId == null) return null;
    } else {
      // Always bind `/files` to this episode id. Series detail used to copy `/item`'s first
      // episode pick-list onto a resume stub (S1 E13 label, E1 video).
      final files = await catalog.openFiles(episodeId: episodeId);
      final preferenceKey = sushiVariantPreferenceKeyFor(item);
      final localPreference = preferenceKey == null ? null : await sushiReadVariantPreference(preferenceKey);
      // fileId is the version already on screen. Preference is only quality + delivery, so two
      // "1080 hard sub" uploads both match and the first one would replace the viewer's pick.
      final lockSelected = fileId != null && fileId != 0;
      streams = sushiBuildMediaStreams(
        files.files,
        preferredFileId: fileId ?? files.lastFileId,
        localPreference: lockSelected ? null : localPreference,
        lockPreferredFile: lockSelected,
      );
      fileId = sushiFileIdFromVersionStreamId(streams.currentVersionStream?.id);
      final overlay = sushiUserDataFromFiles(files);
      item = item.copyWith(
        overview: sushiOverviewWithFileRunTime(
          item.overview,
          files.files,
          lastFileId: fileId ?? files.lastFileId,
        ),
        mediaStreams: streams,
        // Queue stubs can carry the previous episode's resume ticks. Drop position
        // here; sushiOverlayResumeOnEpisode reapplies it only when this episode matches.
        userData: overlay ??
            item.userData.copyWith(
              playbackPositionTicks: 0,
              progress: 0,
            ),
      );
    }
  }

  if (item is! MovieModel && item is! EpisodeModel) return null;

  var playing = item;
  if (playing is EpisodeModel) {
    final seasonQueue = await sushiEpisodeQueueFor(playing, catalog);
    if (seasonQueue.isNotEmpty) {
      episodeQueue = seasonQueue;
    }
    final parentTmdb = sushiTmdbIdFromItemId(playing.parentId ?? '');
    if (parentTmdb != null) {
      final resume = await sushiContinueFind(tmdbId: parentTmdb, kind: SushiKind.series);
      playing = sushiOverlayResumeOnEpisode(playing, resume);
      item = playing;
    }
  }
  final List<ItemBaseModel> queue = playing is EpisodeModel &&
          episodeQueue.length > 1 &&
          episodeQueue.any((e) => e.id == playing.id)
      ? List<ItemBaseModel>.of(episodeQueue)
      : const <ItemBaseModel>[];

  if (sync != null) {
    final local = await sync.getSyncedItem(item.id);
    final offlineId = sushiFileIdFromOfflineName(local?.videoFileName);
    // A download of this item is one upload. Another file of the same title must stream,
    // not replay the file that was saved earlier.
    final offlineIsThisFile = fileId == null || offlineId == null || offlineId == fileId;
    if (local != null && offlineIsThisFile && local.videoFile.existsSync()) {
      return SushiPlaybackModel(
        item: item,
        media: Media(url: local.videoFile.path),
        mediaStreams: streams ?? item.streamModel,
        queue: queue,
        episodeId: sushiEpisodeIdFromItemId(playing.id) ?? movieEpisodeId,
      );
    }
  }

  if (fileId == null) return null;

  final episodeId = sushiEpisodeIdFromItemId(playing.id) ?? movieEpisodeId;

  // Never let this reject: the caller awaits it through CancelableOperation.valueOrCancellation,
  // which — unlike every sushiFetch*/sushiPlay call this resolver is built on — rethrows instead
  // of resolving to null, and would otherwise leave the "Loading" dialog stuck forever on a
  // delivery failure (confirmed live: a never-contacted delivery bot's 400 chat not found — now
  // avoided by pre-starting every delivery bot in the Assignment right after /initbot, see
  // sushi_initbot_transport.dart).
  try {
    final url = await sushiResolvePlaybackUrl(fileId: fileId, preferHttpBridge: preferHttpBridge);
    return SushiPlaybackModel(
      item: item,
      media: Media(url: url),
      mediaStreams: streams ?? item.streamModel,
      queue: queue,
      episodeId: episodeId,
    );
  } catch (e, st) {
    debugPrint('[sushi] play resolve failed: $e\n$st');
    return null;
  }
}
