import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/providers/items/series_details_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

class EpisodeDetailModel {
  final SeriesModel? series;
  final List<EpisodeModel> episodes;
  final EpisodeModel? episode;
  final List<Person> guestActors;
  EpisodeDetailModel({
    this.series,
    this.episodes = const [],
    this.episode,
    this.guestActors = const [],
  });

  EpisodeDetailModel copyWith({
    SeriesModel? series,
    List<EpisodeModel>? episodes,
    EpisodeModel? episode,
    List<Person>? guestActors,
  }) {
    return EpisodeDetailModel(
      series: series ?? this.series,
      episodes: episodes ?? this.episodes,
      episode: episode ?? this.episode,
      guestActors: guestActors ?? this.guestActors,
    );
  }
}

final episodeDetailsProvider =
    StateNotifierProvider.autoDispose.family<EpisodeDetailsProvider, EpisodeDetailModel, String>((ref, id) {
  return EpisodeDetailsProvider(ref);
});

class EpisodeDetailsProvider extends StateNotifier<EpisodeDetailModel> {
  EpisodeDetailsProvider(this.ref) : super(EpisodeDetailModel());

  final Ref ref;

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    Future<Response?> load() async {
      try {
        if (item is! EpisodeModel) return null;
        final seriesId = item.parentId ?? '';
        final series = seriesId.isNotEmpty ? ref.read(seriesDetailsProvider(seriesId)) : null;
        var episode = item;
        final episodeId = sushiEpisodeIdFromItemId(item.id);
        if (episodeId != null && item.mediaStreams.versionStreams.isEmpty) {
          final files = await ref.read(sushiCatalogControllerProvider).openFiles(episodeId: episodeId);
          final overlay = sushiUserDataFromFiles(files);
          final preferenceKey = sushiVariantPreferenceKeyFor(item);
          final localPreference =
              preferenceKey == null ? null : await sushiReadVariantPreference(preferenceKey);
          episode = item.copyWith(
            mediaStreams: sushiBuildMediaStreams(
              files.files,
              preferredFileId: files.lastFileId,
              localPreference: localPreference,
            ),
            overview: sushiOverviewWithFileRunTime(
              item.overview,
              files.files,
              lastFileId: files.lastFileId,
            ),
            userData: (item.userData.playbackPositionTicks == 0 && !item.userData.played && overlay != null)
                ? overlay
                : item.userData,
          );
        }
        state = EpisodeDetailModel(
          series: series,
          episodes: series?.availableEpisodes ?? [episode],
          episode: episode,
        );
        sushiPlayWarmup.scheduleFromStreams(episode.mediaStreams);
        return null;
      } catch (e) {
        _tryToCreateOfflineState(item);
        return null;
      }
    }

    return SushiScreenTelemetry.trackLoad(
      screen: 'episode_detail',
      phase: 'fetch',
      load: load,
    );
  }

  Future<void> _tryToCreateOfflineState(ItemBaseModel item) async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final episodeModel = (await syncNotifier.getSyncedItem(item.id))?.itemModel as EpisodeModel?;
    if (episodeModel == null) return;
    final seriesSyncedItem = await syncNotifier.getSyncedItem(episodeModel.parentBaseModel.id);
    if (seriesSyncedItem == null) return;
    final seriesModel = seriesSyncedItem.itemModel as SeriesModel?;
    if (seriesModel == null) return;
    final episodes = (await syncNotifier.getNestedChildren(seriesSyncedItem))
        .map((e) => e.itemModel)
        .whereType<EpisodeModel>()
        .toList();
    state = state.copyWith(
      series: seriesModel,
      episode: episodes.firstWhereOrNull((element) => element.id == item.id),
      episodes: episodes,
    );
  }

  void updateEpisode(EpisodeModel episode) {
    state = state.copyWith(episode: episode);
    sushiPlayWarmup.scheduleFromStreams(episode.mediaStreams);
  }
}
