import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_season_availability.dart';

EpisodeModel _episode(int n) {
  return EpisodeModel(
    seriesName: 'Ted Lasso',
    season: 1,
    episode: n,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'E$n',
    id: 'sushi_ep_$n',
    overview: const OverviewModel(),
    parentId: 'sushi_tmdb_97546',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: 1.78,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeasonModel _season(List<EpisodeModel> episodes, {int episodeCount = 10}) {
  return SeasonModel(
    parentImages: null,
    seasonName: 'Season 1',
    episodes: episodes,
    episodeCount: episodeCount,
    seriesId: 'sushi_tmdb_97546',
    season: 1,
    seriesName: 'Ted Lasso',
    name: 'Season 1',
    id: 'sushi_season_sushi_tmdb_97546_1',
    overview: const OverviewModel(),
    parentId: 'sushi_tmdb_97546',
    playlistId: null,
    images: null,
    childCount: episodeCount,
    primaryRatio: 0.7,
    userData: UserData(unPlayedItemCount: episodeCount),
    canDelete: false,
    canDownload: true,
  );
}

SeriesModel _series({
  List<EpisodeModel> episodes = const [],
  List<SeasonModel>? seasons,
}) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: 'Ted Lasso',
    id: 'sushi_tmdb_97546',
    playlistId: null,
    overview: const OverviewModel(),
    parentId: null,
    images: null,
    childCount: 10,
    primaryRatio: null,
    userData: const UserData(),
    availableEpisodes: episodes,
    seasons: seasons,
  );
}

void main() {
  test('season index hides the stub play-target episode rail', () {
    final e1 = _episode(1);
    final e2 = _episode(2);
    final series = _series(
      episodes: [e1, e2],
      seasons: [_season([e1, e2], episodeCount: 10)],
    );
    expect(sushiShowSeriesEpisodeRail(series), isFalse);
  });

  test('legacy fat item with no season index still shows the episode rail', () {
    final series = _series(episodes: [_episode(1), _episode(2), _episode(3)]);
    expect(sushiShowSeriesEpisodeRail(series), isTrue);
  });

  test('empty availableEpisodes hides the rail', () {
    expect(sushiShowSeriesEpisodeRail(_series()), isFalse);
  });

  test('a season with nothing ingested yet never shows the watched tick', () {
    // Nothing has been ingested for this season: no episodes are known at all, even though
    // the TMDB index (episodeCount/childCount) reports a full season exists.
    final season = _season(const [], episodeCount: 10);
    expect(sushiSeasonAvailableEpisodeCount(season), 0);
    expect(sushiSeasonShowWatchedTick(season), isFalse);
    expect(sushiSeasonPosterCountText(season), '0/10');
  });

  test('a partially-ingested season shows the on-disk count, not a false tick', () {
    final season = _season(
      [_episode(1), _episode(2), _episode(3), _episode(4), _episode(5)],
      episodeCount: 27,
    );
    expect(sushiSeasonAvailableEpisodeCount(season), 5);
    expect(sushiSeasonShowWatchedTick(season), isFalse);
    expect(sushiSeasonPosterCountText(season), '5/27');
  });

  test('a fully-ingested, partly-watched season shows watched/total', () {
    final episodes = [
      for (var n = 1; n <= 20; n++)
        n == 1 ? _episode(n).copyWith(userData: const UserData(played: true)) : _episode(n),
    ];
    final season = _season(episodes, episodeCount: 20).copyWith(
      userData: const UserData(unPlayedItemCount: 19, played: false),
    );
    expect(sushiSeasonShowWatchedTick(season), isFalse);
    expect(sushiSeasonPosterCountText(season), '1/20');
  });

  test('a fully-ingested, unwatched season shows 0/total', () {
    final season = _season([_episode(1), _episode(2)], episodeCount: 2);
    expect(sushiSeasonPosterCountText(season), '0/2');
  });

  test('a fully-ingested, fully-watched season shows the tick', () {
    final watched = [
      for (final e in [_episode(1), _episode(2)])
        e.copyWith(userData: e.userData.copyWith(played: true)),
    ];
    final season = _season(watched, episodeCount: 2);
    expect(sushiSeasonShowWatchedTick(season), isTrue);
  });

  test('lite /item play-target is not a complete season list', () {
    final season = _season([_episode(1)], episodeCount: 24);
    expect(sushiSeasonEpisodeListComplete(season), isFalse);
  });

  test('loaded season matching TMDB count is complete', () {
    final season = _season([_episode(1), _episode(2)], episodeCount: 2);
    expect(sushiSeasonEpisodeListComplete(season), isTrue);
  });
}
