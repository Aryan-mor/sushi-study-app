import 'package:collection/collection.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';

/// Header Play on the series page follows watch progress, walking season/episode numbers
/// directly instead of Fladder's array-position `nextUp` (which falls back to the very first
/// episode once the last-known episode is watched — wrapping S3E6-finished back to S1E1).
/// Never watched -> first episode. In-progress -> that episode. Finished -> the next catalog
/// episode, or a placeholder only when the season index still claims episodes that are not
/// loaded yet. Caught up on every catalog episode -> stay on the last one. A continue-watching
/// stub (`sushi_ep_stub_…`) is not a catalog episode and must not advance the button.
EpisodeModel? sushiSeriesPlayableNextUp(SeriesModel? series) {
  if (series == null) return null;
  final episodes = (series.availableEpisodes ?? const <EpisodeModel>[])
      .where((e) => e.season > 0 && e.status == EpisodeStatus.available && !sushiEpisodeIsCatalogStub(e))
      .sorted(_bySeasonEpisode);
  if (episodes.isEmpty) return null;

  final inProgress = episodes.lastWhereOrNull((e) => !e.userData.played && e.userData.progress != 0);
  if (inProgress != null) return inProgress;

  final lastWatched = episodes.lastWhereOrNull((e) => e.userData.played);
  if (lastWatched == null) return episodes.first;

  final knownNext = episodes.firstWhereOrNull((e) => !e.userData.played && _isAfter(e, lastWatched));
  if (knownNext != null) return knownNext;

  return _sushiSyntheticNextEpisode(series, lastWatched) ?? lastWatched;
}

int _bySeasonEpisode(EpisodeModel a, EpisodeModel b) {
  final bySeason = a.season.compareTo(b.season);
  return bySeason != 0 ? bySeason : a.episode.compareTo(b.episode);
}

bool _isAfter(EpisodeModel candidate, EpisodeModel lastWatched) {
  if (candidate.season != lastWatched.season) return candidate.season > lastWatched.season;
  return candidate.episode > lastWatched.episode;
}

/// Every known episode up to and including [lastWatched] is finished — the client just hasn't
/// ingested whatever comes after it. Assume "same season, next episode number" unless the
/// season index says that season is already complete, in which case roll into the next season.
EpisodeModel? _sushiSyntheticNextEpisode(SeriesModel series, EpisodeModel lastWatched) {
  final seasons = series.seasons;
  final currentSeason = seasons?.firstWhereOrNull((s) => s.season == lastWatched.season);
  final seasonTotal = currentSeason != null && currentSeason.episodeCount > 0 ? currentSeason.episodeCount : null;

  if (seasonTotal == null || lastWatched.episode < seasonTotal) {
    return sushiEpisodeStub(series, season: lastWatched.season, episode: lastWatched.episode + 1);
  }

  final nextSeason = seasons?.firstWhereOrNull((s) => s.season == lastWatched.season + 1);
  if (nextSeason == null) return null;
  return sushiEpisodeStub(series, season: nextSeason.season, episode: 1);
}
