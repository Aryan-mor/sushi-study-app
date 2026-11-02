import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_next_up.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeModel _episode({
  required String id,
  required int season,
  required int episode,
  bool played = false,
  double progress = 0,
}) {
  return EpisodeModel(
    seriesName: 'Show',
    season: season,
    episode: episode,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Ep $episode',
    id: id,
    overview: const OverviewModel(),
    parentId: 'sushi_tmdb_1',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: 1.78,
    userData: UserData(played: played, progress: progress),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeasonModel _season({required int season, required int episodeCount}) {
  return SeasonModel(
    parentImages: null,
    seasonName: 'Season $season',
    episodeCount: episodeCount,
    seriesId: 'sushi_tmdb_1',
    season: season,
    seriesName: 'Show',
    name: 'Season $season',
    id: 'sushi_season_sushi_tmdb_1_$season',
    overview: const OverviewModel(),
    parentId: 'sushi_tmdb_1',
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
  required List<EpisodeModel> episodes,
  List<SeasonModel>? seasons,
}) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: 'Show',
    id: 'sushi_tmdb_1',
    playlistId: null,
    overview: const OverviewModel(),
    parentId: null,
    images: null,
    childCount: episodes.length,
    primaryRatio: null,
    userData: const UserData(),
    availableEpisodes: episodes,
    seasons: seasons,
  );
}

void main() {
  test('finishing the last known episode of a season synthesizes episode + 1 instead of wrapping to S1E1', () {
    final series = _series(
      episodes: [
        _episode(id: 'sushi_ep_1', season: 1, episode: 1, played: true),
        _episode(id: 'sushi_ep_2', season: 1, episode: 2, played: true),
        _episode(id: 'sushi_ep_3', season: 3, episode: 5, played: true),
        _episode(id: 'sushi_ep_4', season: 3, episode: 6, played: true),
      ],
      seasons: [
        _season(season: 1, episodeCount: 2),
        _season(season: 3, episodeCount: 27),
      ],
    );

    final next = sushiSeriesPlayableNextUp(series);
    expect(next?.season, 3);
    expect(next?.episode, 7);
  });

  test('finishing the last episode of a fully-known season rolls into the next season episode 1', () {
    final series = _series(
      episodes: [
        _episode(id: 'sushi_ep_1', season: 1, episode: 1, played: true),
        _episode(id: 'sushi_ep_2', season: 1, episode: 2, played: true),
      ],
      seasons: [
        _season(season: 1, episodeCount: 2),
        _season(season: 2, episodeCount: 10),
      ],
    );

    final next = sushiSeriesPlayableNextUp(series);
    expect(next?.season, 2);
    expect(next?.episode, 1);
  });

  test('caught up on the last catalog episode stays there instead of wrapping to S1E1', () {
    final series = _series(
      episodes: [
        _episode(id: 'sushi_ep_1', season: 1, episode: 1, played: true),
        _episode(id: 'sushi_ep_2', season: 1, episode: 2, played: true),
      ],
      seasons: [
        _season(season: 1, episodeCount: 2),
      ],
    );

    expect(sushiSeriesPlayableNextUp(series)?.id, 'sushi_ep_2');
  });

  test('a continue stub past the last catalog episode does not advance play', () {
    final series = _series(
      episodes: [
        _episode(id: 'sushi_ep_1', season: 1, episode: 1, played: true),
        _episode(id: 'sushi_ep_15', season: 1, episode: 15, played: true),
        _episode(id: 'sushi_ep_stub_sushi_tmdb_1_1_16', season: 1, episode: 16),
      ],
      seasons: [
        _season(season: 1, episodeCount: 15),
      ],
    );

    expect(sushiSeriesPlayableNextUp(series)?.id, 'sushi_ep_15');
  });

  test('a known later episode is preferred over synthesizing one', () {
    final series = _series(
      episodes: [
        _episode(id: 'sushi_ep_1', season: 1, episode: 1, played: true),
        _episode(id: 'sushi_ep_2', season: 1, episode: 2),
      ],
      seasons: [
        _season(season: 1, episodeCount: 2),
      ],
    );

    final next = sushiSeriesPlayableNextUp(series);
    expect(next?.id, 'sushi_ep_2');
  });
}
