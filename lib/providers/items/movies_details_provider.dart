import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_movie_watch_state.dart';
import 'package:fladder/sushi/providers/sushi_trailer_provider.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

part 'movies_details_provider.g.dart';

@riverpod
class MovieDetails extends _$MovieDetails {
  int _loadGeneration = 0;
  bool _disposed = false;
  late final void Function() _onPlaybackPref;

  late final JellyService api = ref.read(jellyApiProvider);

  @override
  MovieModel? build(String arg) {
    _onPlaybackPref = () {
      if (_disposed) return;
      final current = state;
      if (current == null) return;
      unawaited(fetchDetails(current));
    };
    sushiWatchAccountPlaybackPref(_onPlaybackPref);
    ref.onDispose(() {
      sushiUnwatchAccountPlaybackPref(_onPlaybackPref);
      _disposed = true;
      _loadGeneration++;
    });
    return null;
  }

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(MovieModel? next) {
          if (_disposed || loadGen != _loadGeneration) return;
          state = next;
        }

        if (item is MovieModel) {
          apply(state ?? item);
        }

        if (item is! MovieModel) return null;
        final tmdbId = sushiTmdbIdFromItemId(item.id);
        if (tmdbId == null) return null;

        // Catalog `/item` has no UserData. Enrich from the already-patched
        // provider state when present so a post-play refetch cannot wipe resume
        // with the original 0% route item. Then overlay continue-watching.
        final enrichBase = state ?? item;
        final catalog = ref.read(sushiCatalogControllerProvider);
        final cached = await catalog.peekTitle(tmdbId: tmdbId, kind: SushiKind.movie);
        if (cached?.page != null) {
          // Drop a trailer result locked in before this page had a key.
          ref.invalidate(sushiTrailerStateProvider((itemId: item.id, kind: SushiKind.movie)));
          final localPreference = await _localVariantPreference(enrichBase);
          var painted = sushiEnrichMovieModel(
            enrichBase,
            cached!.page!,
            cached.files,
            preferredFileId: cached.lastFileId,
            localPreference: localPreference,
          );
          painted = await _paintWatchState(painted, files: cached.filesRes);
          painted = sushiPreservePickedMovieFile(painted, state);
          if (loadGen != _loadGeneration) return null;
          apply(painted);
          sushiPlayWarmup.scheduleFromStreams(painted.mediaStreams);
          unawaited(_sushiRefreshMovie(enrichBase, tmdbId, loadGen));
          return null;
        }
        await _sushiRefreshMovie(enrichBase, tmdbId, loadGen);
        return null;
      } catch (e) {
        return null;
      }
    }

    return SushiScreenTelemetry.trackLoad(
      screen: 'movie_detail',
      phase: 'fetch',
      load: load,
    );
  }

  Future<void> _sushiRefreshMovie(MovieModel item, int tmdbId, int loadGen) async {
    var filesKnown = false;
    try {
      final snap = await ref.read(sushiCatalogControllerProvider).openTitle(
            tmdbId: tmdbId,
            kind: SushiKind.movie,
          );
      if (_disposed || loadGen != _loadGeneration) return;
      if (snap.page == null) {
        log('[sushi] movie details: itemRes null tmdbId=$tmdbId');
        return;
      }
      // openTitle may have just written trailerKey. The button peeks once and
      // keeps that result, so reread after the page lands.
      ref.invalidate(sushiTrailerStateProvider((itemId: item.id, kind: SushiKind.movie)));
      final enrichBase = state ?? item;
      final localPreference = await _localVariantPreference(enrichBase);
      var next = sushiEnrichMovieModel(
        enrichBase,
        snap.page!,
        snap.files,
        preferredFileId: snap.lastFileId,
        localPreference: localPreference,
      );
      next = await _paintWatchState(next, files: snap.filesRes);
      next = sushiPreservePickedMovieFile(next, state);
      if (_disposed || loadGen != _loadGeneration) return;
      state = next;
      filesKnown = snap.filesKnown;
      sushiPlayWarmup.scheduleFromStreams(state?.mediaStreams);
    } finally {
      // A timed-out /files is not "no file". Home rows are playable; Request waits
      // until the file list actually arrived.
      if (_disposed || loadGen != _loadGeneration || !filesKnown) return;
      ref.read(sushiTitleResolvedProvider.notifier).markResolved(item.id);
    }
  }

  void setMediaStreamHelper(MediaStreamsModel changed) {
    if (_disposed) return;
    state = state?.copyWith(mediaStreams: changed);
    sushiPlayWarmup.scheduleFromStreams(changed);
  }

  void patchUserData(UserData userData) {
    if (_disposed) return;
    final current = state;
    if (current == null) return;
    _loadGeneration++;
    state = current.copyWith(userData: userData);
  }

  Future<SushiMediaVariantPreference?> _localVariantPreference(ItemBaseModel item) async {
    final key = sushiVariantPreferenceKeyFor(item);
    if (key == null) return null;
    return sushiReadVariantPreference(key);
  }

  Future<MovieModel> _paintWatchState(MovieModel movie, {SushiFilesRes? files}) {
    return sushiLoadAndPaintMovieWatchState(
      movie,
      playedIds: ref.read(sushiCatalogItemFlagsProvider).playedIds,
      files: files,
    );
  }
}
