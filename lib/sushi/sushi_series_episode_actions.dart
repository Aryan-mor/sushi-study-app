import 'package:collection/collection.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_next_up.dart';

/// Series with no watched or in-progress episode — user must pick season + episode first.
bool sushiSeriesNeedsEpisodePick(SeriesModel? series) {
  if (series == null) return false;
  final episodes = series.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return false;
  return !episodes.any((episode) => episode.userData.played || episode.userData.progress != 0);
}

class SushiSeriesPickerSeason {
  const SushiSeriesPickerSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
    this.episodeCount = 0,
  });

  final int seasonNumber;
  final String name;
  final List<EpisodeModel> episodes;
  final int episodeCount;

  SushiSeriesPickerSeason copyWith({List<EpisodeModel>? episodes}) {
    return SushiSeriesPickerSeason(
      seasonNumber: seasonNumber,
      name: name,
      episodes: episodes ?? this.episodes,
      episodeCount: episodeCount,
    );
  }
}

List<SushiSeriesPickerSeason> sushiSeriesPickerSeasons(SeriesModel series) {
  final indexed = series.seasons;
  if (indexed != null && indexed.isNotEmpty) {
    return [
      for (final season in indexed)
        if (season.season > 0 && season.episodeCount > 0)
          SushiSeriesPickerSeason(
            seasonNumber: season.season,
            name: _sushiPickerSeasonName(season, season.season),
            episodes: season.episodes.where((episode) => episode.playAble).toList(),
            episodeCount: season.episodeCount,
          ),
    ];
  }

  final episodes = series.availableEpisodes?.where((episode) => episode.season > 0).toList() ?? [];
  if (episodes.isEmpty) return const [];

  final bySeason = episodes.episodesBySeason;
  return bySeason.entries
      .map((entry) {
        final seasonMeta = series.seasons?.firstWhereOrNull((season) => season.season == entry.key);
        final name = _sushiPickerSeasonName(seasonMeta, entry.key);
        final seasonEpisodes = entry.value.where((episode) => episode.playAble).toList();
        return SushiSeriesPickerSeason(
          seasonNumber: entry.key,
          name: name,
          episodes: seasonEpisodes,
          episodeCount: seasonEpisodes.length,
        );
      })
      .where((season) => season.episodes.isNotEmpty)
      .toList();
}

String _sushiPickerSeasonName(SeasonModel? seasonMeta, int seasonNumber) {
  if (seasonMeta != null) {
    if (seasonMeta.seasonName.isNotEmpty) return seasonMeta.seasonName;
    if (seasonMeta.name.isNotEmpty) return seasonMeta.name;
  }
  return seasonNumber.toString();
}

/// Header Play on series detail follows watch progress — not row focus.
/// Never-watched → first episode. In-progress → that episode. Finished → next.
EpisodeModel? sushiSeriesDetailPlayTarget(SeriesModel? series) {
  if (series == null) return null;
  return sushiSeriesPlayableNextUp(series);
}

/// Id to send to [markAsPlayed]. Series posters use the catalog TMDB id;
/// next-up reads episode ids (`sushi_ep_*`), so the series page must mark
/// the current play-target episode.
///
/// Seasons never have a single flag id — [sushiSeasonMarkPlayed] writes every
/// `sushi_ep_*`. Returning the synthetic `sushi_season_*` id is a no-op for
/// posters (ADR 0028).
String sushiMarkPlayedItemId(ItemBaseModel item) {
  if (item is SeriesModel) {
    return sushiSeriesDetailPlayTarget(item)?.id ?? item.id;
  }
  if (item is SeasonModel) {
    return '';
  }
  return item.id;
}
