import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/sushi/sushi_library_item_ratings.dart';
import 'package:fladder/sushi/sushi_season_user_data.dart';
import 'package:fladder/sushi/sushi_series_details_loader.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';
import 'package:fladder/sushi/sushi_virtual_episode_images.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

/// Merges freshly loaded shelves into [current] without dropping in-flight catalog data.
SeriesModel sushiMergeSeriesSupplementary(
  SeriesModel current, {
  List<ItemBaseModel>? related,
  List<SpecialFeatureModel>? specialFeatures,
}) {
  return current.copyWith(
    related: related ?? current.related,
    specialFeatures: specialFeatures ?? current.specialFeatures,
    overview: current.overview,
  );
}

MovieModel sushiMergeMovieSupplementary(
  MovieModel current, {
  List<ItemBaseModel>? related,
  List<SpecialFeatureModel>? specialFeatures,
}) {
  return current.copyWith(
    related: related ?? current.related,
    specialFeatures: specialFeatures ?? current.specialFeatures,
    overview: current.overview,
  );
}

Future<SeriesModel?> sushiFetchSeriesCoreState(
  Ref ref,
  ItemBaseModel seriesModel,
  SeriesModel? previous,
) async {
  SeriesModel? newState;
  if (SushiEnv.isEnabled) {
    final sushiItem = await sushiFetchLibraryItemDetails(ref, seriesModel.id);
    if (sushiItem != null && sushiItem.model is SeriesModel) {
      newState = (sushiItem.model as SeriesModel).copyWith(
        related: previous?.related ?? const [],
        availableEpisodes: previous?.availableEpisodes ?? const [],
        seasons: previous?.seasons ?? const [],
        canDownload: previous?.canDownload ?? false,
        specialFeatures: previous?.specialFeatures,
      );
    }
  }
  if (newState == null) {
    final api = ref.read(jellyApiProvider);
    final response = await api.usersUserIdItemsItemIdGet(itemId: seriesModel.id);
    if (response.body == null) return null;
    newState = (response.bodyOrThrow as SeriesModel).copyWith(
      related: previous?.related ?? const [],
      availableEpisodes: previous?.availableEpisodes ?? const [],
      seasons: previous?.seasons ?? const [],
      canDownload: previous?.canDownload ?? false,
      specialFeatures: previous?.specialFeatures,
    );
    if (SushiEnv.isEnabled) {
      final raw = await sushiFetchLibraryItemJson(ref, seriesModel.id);
      sushiApplyLibraryItemRatings(ref, seriesModel.id, raw != null ? sushiRatingsFromItemJson(raw) : null);
    }
  }
  return newState;
}

Future<MovieModel?> sushiFetchMovieCoreState(
  Ref ref,
  ItemBaseModel item,
  MovieModel? previous,
) async {
  MovieModel? newState;
  if (SushiEnv.isEnabled) {
    final sushiItem = await sushiFetchLibraryItemDetails(ref, item.id);
    if (sushiItem != null && sushiItem.model is MovieModel) {
      newState = (sushiItem.model as MovieModel).copyWith(
        related: previous?.related ?? const [],
        specialFeatures: previous?.specialFeatures ?? const [],
      );
    }
  }
  if (newState == null) {
    final api = ref.read(jellyApiProvider);
    final response = await api.usersUserIdItemsItemIdGet(itemId: item.id);
    if (response.body == null) return null;
    newState = (response.bodyOrThrow as MovieModel).copyWith(
      related: previous?.related ?? const [],
      specialFeatures: previous?.specialFeatures ?? const [],
    );
    if (SushiEnv.isEnabled) {
      final raw = await sushiFetchLibraryItemJson(ref, item.id);
      sushiApplyLibraryItemRatings(ref, item.id, raw != null ? sushiRatingsFromItemJson(raw) : null);
    }
  }
  return newState;
}

Future<SeriesModel> sushiLoadSeriesCatalogPhase(
  Ref ref,
  SeriesModel base,
  String seriesId, {
  Future<SushiSeriesCatalogLoad>? prefetchCatalog,
}) async {
  final api = ref.read(jellyApiProvider);

  final Response<BaseItemDtoQueryResult?> seasons;
  List<BaseItemDto> episodeItems;
  if (SushiEnv.isEnabled) {
    final catalog = prefetchCatalog != null
        ? await prefetchCatalog
        : await sushiFetchSeriesCatalogBySeason(api, seriesId);
    seasons = catalog.seasons;
    episodeItems = catalog.episodeItems;
  } else {
    seasons = await api.showsSeriesIdSeasonsGet(
      seriesId: seriesId,
      enableUserData: false,
    );
    final episodes = await api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      enableUserData: true,
      fields: sushiEpisodeListFields([
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.candownload,
      ]),
    );
    episodeItems = episodes.body?.items ?? const [];
  }

  final preferenceKey = sushiVariantPreferenceKeyFor(base);
  final localPreference = preferenceKey == null ? null : await sushiReadVariantPreference(preferenceKey);
  final newEpisodes = sushiPrepareEpisodeListMediaStreams(
    ref,
    sushiApplyVirtualEpisodeImages(
      EpisodeModel.episodesFromDto(episodeItems, ref),
      episodeItems,
      ref,
    ),
    localPreference: localPreference,
  );

  final episodesCanDownload = newEpisodes.any((episode) => episode.canDownload == true);

  var newState = base.copyWith(
    seasons: SeasonModel.seasonsFromDto(seasons.body?.items, ref).map(
      (element) {
        final seasonEpisodes = newEpisodes.where((episode) => episode.season == element.season);
        final userData = SushiEnv.isEnabled
            ? sushiSeasonUserDataFromEpisodes(seasonEpisodes)
            : () {
                final unPlayedCount = seasonEpisodes
                    .where((episode) =>
                        episode.status == EpisodeStatus.available && episode.userData.played == false)
                    .length;
                return UserData(
                  unPlayedItemCount: unPlayedCount,
                  played: unPlayedCount == 0,
                );
              }();
        return element.copyWith(
          canDownload: true,
          episodes: seasonEpisodes.toList(),
          userData: userData,
        );
      },
    ).toList(),
  );

  return newState.copyWith(
    canDownload: episodesCanDownload,
    availableEpisodes: newEpisodes,
  );
}

Future<({
  List<ItemBaseModel> related,
  List<SpecialFeatureModel> specialFeatures,
})> sushiLoadSeriesSupplementaryPhase(
  Ref ref,
  String seriesId,
  SeriesModel state,
) async {
  final api = ref.read(jellyApiProvider);

  List<BaseItemDto> specialFeaturesDto;
  try {
    specialFeaturesDto = (await api.itemsItemIdSpecialFeaturesGet(itemId: seriesId)).body ?? [];
  } on Exception catch (e, s) {
    specialFeaturesDto = [];
    log(
      "Failed to get special features for series id $seriesId due to $e",
      level: logging.Level.WARNING.value,
      error: e,
      stackTrace: s,
    );
  }

  final related = await ref.read(relatedUtilityProvider).relatedContent(seriesId);

  return (
    related: related.body ?? const [],
    specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeaturesDto, ref),
  );
}

Future<({
  List<ItemBaseModel> related,
  List<SpecialFeatureModel> specialFeatures,
})> sushiLoadMovieSupplementaryPhase(
  Ref ref,
  String itemId,
  MovieModel state,
) async {
  final api = ref.read(jellyApiProvider);

  List<BaseItemDto> specialFeaturesDto;
  try {
    specialFeaturesDto = (await api.itemsItemIdSpecialFeaturesGet(itemId: itemId)).body ?? [];
  } on Exception catch (e, s) {
    specialFeaturesDto = [];
    log(
      "Failed to get special features for movie id $itemId due to $e",
      level: logging.Level.WARNING.value,
      error: e,
      stackTrace: s,
    );
  }

  final related = await ref.read(relatedUtilityProvider).relatedContent(itemId);

  return (
    related: related.body ?? const [],
    specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeaturesDto, ref),
  );
}

