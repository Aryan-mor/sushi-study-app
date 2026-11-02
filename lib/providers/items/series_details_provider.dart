import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/providers/sushi_trailer_provider.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/sushi/sushi_season_availability.dart';
import 'package:fladder/sushi/sushi_series_selected_episode.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

bool _seriesEpisodeListed(SeriesModel? series, int? filesEpisodeId) {
  if (series == null || filesEpisodeId == null) return false;
  return series.availableEpisodes?.any(
        (episode) => sushiEpisodeIdFromItemId(episode.id) == filesEpisodeId,
      ) ??
      false;
}

final seriesDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeriesDetailViewNotifier, SeriesModel?, String>((ref, id) {
  return SeriesDetailViewNotifier(ref);
});

class SeriesDetailViewNotifier extends StateNotifier<SeriesModel?> {
  SeriesDetailViewNotifier(this.ref) : super(null) {
    _onPlaybackPref = () {
      if (!mounted) return;
      final current = state;
      if (current == null) return;
      unawaited(fetchDetails(current));
    };
    sushiWatchAccountPlaybackPref(_onPlaybackPref);
  }

  final Ref ref;
  int _loadGeneration = 0;
  late final void Function() _onPlaybackPref;

  Future<Response?> fetchDetails(ItemBaseModel seriesModel) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(SeriesModel? next) {
          if (!mounted || loadGen != _loadGeneration) return;
          state = next;
        }

        if (seriesModel is SeriesModel) {
          apply(state ?? seriesModel);
        }

        if (seriesModel is! SeriesModel) return null;
        final tmdbId = sushiTmdbIdFromItemId(seriesModel.id);
        if (tmdbId == null) return null;
        final catalog = ref.read(sushiCatalogControllerProvider);
        final cached = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.series);
        if (cached?.page != null) {
          ref.invalidate(sushiTrailerStateProvider((itemId: seriesModel.id, kind: SushiKind.series)));
          var painted = sushiEnrichSeriesModel(seriesModel, cached!.page!);
          final cachedFilesEpisodeId = cached.page!.episodes.firstOrNull?.episodeId;
          painted = await _paintWatchState(
            painted,
            files: cached.filesRes,
            filesEpisodeId: cachedFilesEpisodeId,
          );
          if (cached.files.isNotEmpty) {
            painted = sushiPreservePickedFiles(
              sushiApplySeriesFiles(
                painted,
                cached.files,
                preferredFileId: cached.lastFileId,
                localPreference: await sushiReadVariantPreference('series:$tmdbId'),
                filesEpisodeId: cachedFilesEpisodeId,
              ),
              state,
            );
            sushiPlayWarmup.scheduleFromStreams(
              (painted.selectedEpisode ?? painted.nextUp)?.mediaStreams,
            );
          }
          apply(painted);
          unawaited(_sushiRefreshSeries(seriesModel, tmdbId, loadGen));
          return null;
        }
        await _sushiRefreshSeries(seriesModel, tmdbId, loadGen);
        return null;
      } catch (e) {
        log("Error fetching series details: $e");
        return null;
      }
    }

    return SushiScreenTelemetry.trackLoad(
      screen: 'series_detail',
      phase: 'fetch',
      load: load,
    );
  }

  Future<void> _sushiRefreshSeries(SeriesModel seriesModel, int tmdbId, int loadGen) async {
    try {
      final catalog = ref.read(sushiCatalogControllerProvider);
      // Cached `/item` + `/episodes` otherwise freeze at the first visit (docs/11 §2).
      // Paint already happened from SQLite; this updates it when the hour is up.
      await catalog.revalidateSeriesStructure(tmdbId: tmdbId);
      if (!mounted || loadGen != _loadGeneration) return;
      final snap = await catalog.openTitle(tmdbId: tmdbId, kind: SushiKind.series);
      if (!mounted || loadGen != _loadGeneration) return;
      if (snap.page == null) {
        log('[sushi] series details: itemRes null tmdbId=$tmdbId');
        return;
      }
      ref.invalidate(sushiTrailerStateProvider((itemId: seriesModel.id, kind: SushiKind.series)));
      var next = sushiEnrichSeriesModel(seriesModel, snap.page!);
      // Resume stub (E13) must land before we pick whose `/files` to fetch. `/item` only
      // wires the first episode (ADR 0028); nextUp before paint is always that row.
      next = await _paintWatchState(next);
      final playEpisodeId = _pickedFilesEpisodeId(next) ?? sushiSeriesPlayFilesEpisodeId(next);
      final firstEpisodeId = snap.page!.episodes.firstOrNull?.episodeId;
      var files = snap.filesRes;
      var filesKnown = snap.filesKnown;
      // Files always belong to a catalog episode id. A continue stub
      // (`sushi_ep_stub_…`) has none — passing null used to glue `/item`'s first
      // episode pick-list onto that stub (Play S1 E15, video S1 E1).
      final filesEpisodeId = playEpisodeId ?? firstEpisodeId;
      if (playEpisodeId != null && playEpisodeId != firstEpisodeId) {
        files = await catalog.openFiles(episodeId: playEpisodeId);
        filesKnown = files.known;
        if (!mounted || loadGen != _loadGeneration) return;
      }
      next = await _paintWatchState(
        next,
        files: files,
        filesEpisodeId: filesEpisodeId,
      );
      final localPreference = await sushiReadVariantPreference('series:$tmdbId');
      if (!mounted || loadGen != _loadGeneration) return;
      state = sushiPreservePickedFiles(
        sushiApplySeriesFiles(
          next,
          files.files,
          preferredFileId: files.lastFileId,
          localPreference: localPreference,
          filesEpisodeId: filesEpisodeId,
        ),
        state,
      );
      // Resume can point at an episode the lite page does not list yet. /files
      // already has the video; attaching it after the season cache lands is what
      // the back-and-reopen used to do by accident.
      if (files.files.isNotEmpty && !_seriesEpisodeListed(state, filesEpisodeId)) {
        await _loadIncompleteSeasons(loadGen);
        if (!mounted || loadGen != _loadGeneration) return;
        final latest = state;
        if (latest != null) {
          final repainted = await _paintWatchState(
            latest,
            files: files,
            filesEpisodeId: filesEpisodeId,
          );
          if (!mounted || loadGen != _loadGeneration) return;
          state = sushiPreservePickedFiles(
            sushiApplySeriesFiles(
              repainted,
              files.files,
              preferredFileId: files.lastFileId,
              localPreference: localPreference,
              filesEpisodeId: filesEpisodeId,
            ),
            state,
          );
        }
      }
      sushiPlayWarmup.scheduleFromStreams(
        (state?.selectedEpisode ?? state?.nextUp)?.mediaStreams,
      );
      if (!mounted || loadGen != _loadGeneration || !filesKnown) return;
      if (files.files.isNotEmpty && !_seriesEpisodeListed(state, filesEpisodeId)) return;
      ref.read(sushiTitleResolvedProvider.notifier).markResolved(seriesModel.id);
      unawaited(_loadIncompleteSeasons(loadGen));
    } catch (e, s) {
      log('[sushi] series details: refresh failed tmdbId=$tmdbId: $e', stackTrace: s);
    }
  }

  /// Catalog episode id of the episode picked from the series-page picker, when it
  /// is still on [series]. Header Play + quality follow the pick (not next-up).
  int? _pickedFilesEpisodeId(SeriesModel series) {
    final pickedId = ref.read(sushiSeriesSelectedEpisodeIdProvider(series.id));
    if (pickedId == null) return null;
    final known = series.availableEpisodes?.any((episode) => episode.id == pickedId) ?? false;
    return known ? sushiEpisodeIdFromItemId(pickedId) : null;
  }

  /// Episode picker: moves header Play and the file/quality picker onto [episode]
  /// without starting playback, then loads that episode's `/files`.
  Future<void> pickEpisode(EpisodeModel episode) async {
    final current = state;
    if (!mounted || current == null) return;
    ref.read(sushiSeriesSelectedEpisodeIdProvider(current.id).notifier).state = episode.id;
    final episodeId = sushiEpisodeIdFromItemId(episode.id);
    final tmdbId = sushiTmdbIdFromItemId(current.id);
    if (episodeId == null || tmdbId == null) return;
    final loadGen = _loadGeneration;
    try {
      final files = await ref.read(sushiCatalogControllerProvider).openFiles(episodeId: episodeId);
      final localPreference = await sushiReadVariantPreference('series:$tmdbId');
      final latest = state;
      if (!mounted || latest == null || loadGen != _loadGeneration) return;
      state = sushiPreservePickedFiles(
        sushiApplySeriesFiles(
          latest,
          files.files,
          preferredFileId: files.lastFileId,
          localPreference: localPreference,
          filesEpisodeId: episodeId,
        ),
        state,
      );
      sushiPlayWarmup.scheduleFromStreams(
        state?.availableEpisodes?.firstWhereOrNull((e) => e.id == episode.id)?.mediaStreams,
      );
    } catch (e, s) {
      log('[sushi] series details: pick episode files failed episodeId=$episodeId: $e', stackTrace: s);
    }
  }

  @override
  void dispose() {
    sushiUnwatchAccountPlaybackPref(_onPlaybackPref);
    _loadGeneration++;
    super.dispose();
  }

  void updateEpisodeInfo(EpisodeModel episode) {
    if (!mounted) return;
    final index = state?.availableEpisodes?.indexWhere((e) => e.id == episode.id);

    final newList = state?.availableEpisodes?.toList() ?? [];
    newList[index ?? 0] = episode;

    if (index != null) {
      state = state?.copyWith(
        availableEpisodes: newList,
      );
    }
    sushiPlayWarmup.scheduleFromStreams(episode.mediaStreams);
  }

  void setCurrentEpisode(EpisodeModel? episodeModel) {
    if (!mounted) return;
    state = state?.copyWith(selectedEpisode: episodeModel);
    sushiPlayWarmup.scheduleFromStreams(episodeModel?.mediaStreams);
  }

  void mergeSeason(int seasonNo, List<EpisodeModel> loaded) {
    if (!mounted) return;
    final current = state;
    if (current == null) return;
    state = sushiMergeSeasonEpisodes(current, seasonNo, loaded);
  }

  Future<List<EpisodeModel>> loadSeason(int seasonNo) async {
    final current = state;
    if (current == null) return const [];
    final tmdbId = sushiTmdbIdFromItemId(current.id);
    if (tmdbId == null) return const [];
    final season = current.seasons?.firstWhereOrNull((s) => s.season == seasonNo);
    if (season != null &&
        season.episodeCount > 0 &&
        season.episodes.length >= season.episodeCount) {
      return season.episodes;
    }
    final wire = await ref.read(sushiCatalogControllerProvider).openSeason(
          tmdbId: tmdbId,
          kind: SushiKind.series,
          seasonNo: seasonNo,
        );
    if (!mounted) return const [];
    final loaded = sushiEpisodesFromWire(current, wire);
    mergeSeason(seasonNo, loaded);
    return loaded;
  }

  Future<SeriesModel> _attachCachedSeasons(SeriesModel series) async {
    final tmdbId = sushiTmdbIdFromItemId(series.id);
    if (tmdbId == null) return series;
    final catalog = ref.read(sushiCatalogControllerProvider);
    var next = series;
    for (final season in series.seasons ?? const []) {
      if (sushiSeasonEpisodeListComplete(
        next.seasons?.firstWhereOrNull((s) => s.season == season.season) ?? season,
      )) {
        continue;
      }
      final wire = await catalog.peekSeason(
        tmdbId: tmdbId,
        kind: SushiKind.series,
        seasonNo: season.season,
      );
      if (wire == null || wire.isEmpty) continue;
      next = sushiMergeSeasonEpisodes(next, season.season, sushiEpisodesFromWire(next, wire));
    }
    return next;
  }

  /// Lite `/item` omits the episode list (ADR 0028). Watched ticks need every
  /// episode, so fill any season the cache did not already have.
  Future<void> _loadIncompleteSeasons(int loadGen) async {
    final seasons = [...?state?.seasons];
    for (final season in seasons) {
      if (!mounted || loadGen != _loadGeneration) return;
      await loadSeason(season.season);
    }
  }

  Future<SeriesModel> _paintWatchState(
    SeriesModel series, {
    SushiFilesRes? files,
    int? filesEpisodeId,
  }) async {
    final tmdbId = sushiTmdbIdFromItemId(series.id);
    final resume = tmdbId == null
        ? null
        : await sushiContinueFind(tmdbId: tmdbId, kind: SushiKind.series);
    final withSeasons = await _attachCachedSeasons(series);
    final extra = await _playedIdsFromMirror(withSeasons);
    if (extra.isNotEmpty) {
      unawaited(ref.read(sushiCatalogItemFlagsProvider.notifier).setPlayedMany(extra, true));
    }
    return sushiPaintSeriesWatchState(
      withSeasons,
      playedIds: {...ref.read(sushiCatalogItemFlagsProvider).playedIds, ...extra},
      resume: resume,
      files: files,
      filesEpisodeId: filesEpisodeId,
    );
  }

  Future<Set<String>> _playedIdsFromMirror(SeriesModel series) async {
    final catalog = ref.read(sushiCatalogControllerProvider);
    final ids = <String>{};
    for (final episode in series.availableEpisodes ?? const []) {
      final episodeId = sushiEpisodeIdFromItemId(episode.id);
      if (episodeId == null || episodeId <= 0) continue;
      if (await catalog.isEpisodeWatched(episodeId)) ids.add(episode.id);
    }
    return ids;
  }
}
