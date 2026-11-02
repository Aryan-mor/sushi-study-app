import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';

int sushiSeasonTotalEpisodeCount(SeasonModel season) {
  if (season.episodeCount > 0) return season.episodeCount;
  if (season.episodes.isNotEmpty) return season.episodes.length;
  return season.childCount ?? 0;
}

/// `season.episodes` is the client's authoritative on-disk list once enriched (possibly empty
/// when nothing in the season has been ingested yet) — `childCount`/`episodeCount` are TMDB
/// totals, not on-disk counts, so they must never be used as an "available" fallback here. Doing
/// so previously made an entirely un-ingested season (0 known episodes) look fully watched,
/// since `onDisk` came out equal to `total` by coincidence.
int sushiSeasonAvailableEpisodeCount(SeasonModel season) {
  return season.episodes.where((episode) => episode.status == EpisodeStatus.available).length;
}

/// ADR 0028 lite `/item` attaches one play-target. That is not the season.
bool sushiSeasonEpisodeListComplete(SeasonModel season) {
  if (season.episodes.isEmpty) return false;
  if (season.episodeCount <= 0) return true;
  return season.episodes.length >= season.episodeCount;
}

/// True when every on-disk episode in the season is marked played (Fladder check icon).
bool sushiSeasonShowWatchedTick(SeasonModel season) {
  final total = sushiSeasonTotalEpisodeCount(season);
  final onDisk = sushiSeasonAvailableEpisodeCount(season);
  if (onDisk < total) return false;
  final playable = season.episodes.where((episode) => episode.status == EpisodeStatus.available);
  if (playable.isEmpty) return false;
  return playable.every((episode) => episode.userData.played);
}

/// Season poster badge: `3/10` partial on disk, `0/10` none,
/// `1/20` watched/total when the season is fully on disk, else tick.
String? sushiSeasonPosterCountText(SeasonModel season) {
  final total = sushiSeasonTotalEpisodeCount(season);
  if (total <= 0) return null;
  final onDisk = sushiSeasonAvailableEpisodeCount(season);
  if (onDisk < total) return '$onDisk/$total';
  final unplayed = season.userData.unPlayedItemCount;
  if (unplayed == null || unplayed <= 0) return null;
  final watched = (total - unplayed).clamp(0, total);
  return '$watched/$total';
}

/// ADR 0028: series home shows the season index, not a stub of the play-target
/// (+ continue). A fat legacy `/item` with no season index still paints the
/// episode rail from `availableEpisodes`.
bool sushiShowSeriesEpisodeRail(SeriesModel details) {
  final episodes = details.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return false;
  final seasons = details.seasons;
  if (seasons != null && seasons.isNotEmpty) return false;
  return true;
}
