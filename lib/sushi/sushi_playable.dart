import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';

bool _hasReadyStreams(EpisodeModel episode) => episode.mediaStreams.versionStreams.isNotEmpty;

/// Whether Play / Sync belong on this item's overflow menu.
///
/// Compact [sushiRowToItemBaseModel] cards have no `/files` yet — hide Play/Sync until the
/// detail enrich attaches at least one ready version stream.
bool sushiItemHasPlaybackActions(ItemBaseModel item) {
  switch (item) {
    case MovieModel movie:
      return movie.mediaStreams.versionStreams.isNotEmpty;
    case SeriesModel series:
      return series.availableEpisodes?.any(_hasReadyStreams) ?? false;
    case SeasonModel season:
      return season.episodes.any(_hasReadyStreams);
    case EpisodeModel episode:
      return _hasReadyStreams(episode);
    default:
      return false;
  }
}

/// We carry this series (season index or catalog episode ids). Request is for TMDB-only titles
/// (ADR 0014), not for a catalog show whose header play-target has no file yet.
bool sushiSeriesCarried(SeriesModel series) {
  if (series.seasons?.any((s) => s.episodeCount > 0) == true) return true;
  return series.availableEpisodes?.any((e) => e.playAble) == true;
}
