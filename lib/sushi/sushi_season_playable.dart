import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';

/// Virtual / TMDB-only seasons have no catalog row — hide Jellyfin user-data actions.
bool sushiSeasonHasPlayableEpisodes(SeasonModel season) {
  
  if (season.episodes.isEmpty) return false;
  return season.episodes.any((episode) => episode.status == EpisodeStatus.available);
}
