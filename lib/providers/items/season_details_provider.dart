import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/items/series_details_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_season_user_data.dart';
import 'package:fladder/sushi/sushi_virtual_episode_images.dart';
import 'package:logging/logging.dart' as logging;

final seasonDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeasonDetailsNotifier, SeasonModel?, String>((ref, id) {
  return SeasonDetailsNotifier(ref);
});

class SeasonDetailsNotifier extends StateNotifier<SeasonModel?> {
  SeasonDetailsNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<Response?> fetchDetails(String seasonId, {SeasonModel? hint}) async {
    if (SushiConfig.isEnabled) {
      await _loadSushiSeason(hint);
      return null;
    }

    SeasonModel? newState = hint;

    final season = await api.usersUserIdItemsItemIdGet(itemId: seasonId);
    if (season.body != null) newState = season.bodyOrThrow as SeasonModel;

    final seriesId = newState?.seriesId ?? "";
    if (seriesId.isEmpty) {
      state = newState;
      return season;
    }

    final episodes = await api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      seasonId: newState?.id ?? seasonId,
      season: newState?.season,
      enableUserData: true,
      fields: sushiEpisodeListFields([
        ItemFields.overview,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.parentid,
        ItemFields.externalurls,
      ]),
    );

    List<BaseItemDto> specialFeatures;
    try {
      specialFeatures = (await api.itemsItemIdSpecialFeaturesGet(itemId: seasonId)).body ?? [];
    } on Exception catch (e, s) {
      specialFeatures = [];
      log("Failed to get special features for season id $seasonId due to $e",
          level: logging.Level.WARNING.value, error: e, stackTrace: s);
    }

    newState = newState?.copyWith(
        episodes: sushiApplyVirtualEpisodeImages(
          EpisodeModel.episodesFromDto(episodes.body?.items, ref).toList(),
          episodes.body?.items,
          ref,
        ),
        specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeatures, ref).toList());
    if (newState != null) {
      newState = newState.copyWith(
        userData: sushiSeasonUserDataFromEpisodes(newState.episodes),
      );
    }
    state = newState;
    return season;
  }

  Future<void> _loadSushiSeason(SeasonModel? hint) async {
    state = hint;
    if (hint == null) return;
    final tmdbId = sushiTmdbIdFromItemId(hint.seriesId);
    if (tmdbId == null) return;
    final wire = await ref.read(sushiCatalogControllerProvider).openSeason(
          tmdbId: tmdbId,
          kind: SushiKind.series,
          seasonNo: hint.season,
        );
    final series = ref.read(seriesDetailsProvider(hint.seriesId)) ??
        SeriesModel(
          originalTitle: '',
          sortName: '',
          status: '',
          name: hint.seriesName,
          id: hint.seriesId,
          overview: hint.overview,
          parentId: null,
          playlistId: null,
          images: hint.parentImages,
          childCount: hint.episodeCount,
          primaryRatio: null,
          userData: const UserData(),
        );
    final loaded = sushiEpisodesFromWire(series, wire);
    state = hint.copyWith(
      episodes: loaded,
      userData: sushiSeasonUserDataFromEpisodes(loaded),
    );
    ref.read(seriesDetailsProvider(hint.seriesId).notifier).mergeSeason(hint.season, loaded);
  }
}
