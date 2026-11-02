import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/sushi/sushi_virtual_episode_images.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:http/http.dart' as http;

/// Series catalog: seasons + all episodes in parallel (two HTTP calls).
class SushiSeriesCatalogLoad {
  const SushiSeriesCatalogLoad({
    required this.seasons,
    required this.episodeItems,
  });

  final Response<BaseItemDtoQueryResult?> seasons;
  final List<dto.BaseItemDto> episodeItems;
}

List<ItemFields> _sushiSeriesEpisodeListFields() {
  return sushiEpisodeListFields([
    ItemFields.mediastreams,
    ItemFields.mediasources,
    ItemFields.overview,
    ItemFields.candownload,
  ]);
}

Future<SushiSeriesCatalogLoad> sushiFetchSeriesCatalogBySeason(JellyService api, String seriesId) async {
  final fields = _sushiSeriesEpisodeListFields();
  final results = await Future.wait([
    api.showsSeriesIdSeasonsGet(
      seriesId: seriesId,
      enableUserData: false,
    ),
    api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      enableUserData: true,
      fields: fields,
    ),
  ]);

  final seasons = results[0];
  final episodes = results[1];
  return SushiSeriesCatalogLoad(
    seasons: seasons,
    episodeItems: episodes.body?.items ?? const [],
  );
}

/// Legacy wrapper — prefer [sushiFetchSeriesCatalogBySeason].
Future<
    ({
      Response<BaseItemDtoQueryResult?> seasons,
      Response<BaseItemDtoQueryResult?> episodes,
    })> sushiFetchSeriesSeasonsAndEpisodes(
  JellyService api,
  String seriesId,
) async {
  final load = await sushiFetchSeriesCatalogBySeason(api, seriesId);
  return (
    seasons: load.seasons,
    episodes: Response<BaseItemDtoQueryResult?>(
      http.Response('', 200),
      BaseItemDtoQueryResult(
        items: load.episodeItems,
        totalRecordCount: load.episodeItems.length,
      ),
    ),
  );
}
