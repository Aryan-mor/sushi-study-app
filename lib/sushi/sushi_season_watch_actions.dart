import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/items/series_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_season_availability.dart';

/// Catalog episode ids posters / next-up actually paint (`sushi_ep_<n>`).
/// Synthetic `sushi_season_*` and continue stubs are skipped.
List<String> sushiSeasonPlayedFlagIds(Iterable<EpisodeModel> episodes) {
  return [
    for (final episode in episodes)
      if (sushiEpisodeIdFromItemId(episode.id) != null) episode.id,
  ];
}

/// Mark every catalog episode in the season. Lite `/item` (ADR 0028) attaches
/// **one** play-target — that is not the season. Always `loadSeason` /
/// `openSeason` when the list is short of `episodeCount`. Never write `season.id`.
///
/// `markManyPlayed` paints locally and sends `WatchedEvent` so `user_episode_state`
/// survives refresh, logout, and another device. Do not `fetchDetails` the series
/// after: thin `/item` wipes the loaded season list. Merge locally; posters paint
/// from `playedIds`.
Future<void> sushiSeasonMarkPlayed(WidgetRef ref, SeasonModel season, bool played) async {
  final episodes = await sushiSeasonEpisodesForWatch(ref, season);
  final episodeIds = sushiSeasonPlayedFlagIds(episodes);
  debugPrint(
    '[sushi] season_mark played=$played season=${season.season} n=${episodeIds.length} have=${episodes.length} total=${season.episodeCount} id=${season.id}',
  );
  if (episodeIds.isEmpty) {
    debugPrint('[sushi] season_mark skip empty season=${season.season} id=${season.id}');
    return;
  }
  await ref.read(userProvider.notifier).markManyPlayed(played, episodeIds);
  final seriesId = season.seriesId;
  if (seriesId.isEmpty) return;
  if (ref.read(seriesDetailsProvider(seriesId)) == null) return;
  ref.read(seriesDetailsProvider(seriesId).notifier).mergeSeason(season.season, episodes);
}

Future<List<EpisodeModel>> sushiSeasonEpisodesForWatch(WidgetRef ref, SeasonModel season) async {
  final seriesId = season.seriesId;
  if (seriesId.isNotEmpty) {
    final seriesProv = seriesDetailsProvider(seriesId);
    if (ref.read(seriesProv) != null) {
      return ref.read(seriesProv.notifier).loadSeason(season.season);
    }
  }
  if (sushiSeasonEpisodeListComplete(season)) return season.episodes;
  if (seriesId.isEmpty) return season.episodes;
  final tmdbId = sushiTmdbIdFromItemId(seriesId);
  if (tmdbId == null) return season.episodes;
  final wire = await ref.read(sushiCatalogControllerProvider).openSeason(
        tmdbId: tmdbId,
        kind: SushiKind.series,
        seasonNo: season.season,
      );
  return sushiEpisodesFromWire(_sushiSeasonParentStub(season), wire);
}

SeriesModel _sushiSeasonParentStub(SeasonModel season) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: season.seriesName,
    id: season.seriesId,
    overview: season.overview,
    parentId: null,
    playlistId: null,
    images: season.parentImages,
    childCount: season.episodeCount,
    primaryRatio: null,
    userData: const UserData(),
  );
}
