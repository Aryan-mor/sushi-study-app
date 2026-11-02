import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:flutter_test/flutter_test.dart';
EpisodeModel _episode({required String id, required int episode}) {
  return EpisodeModel(
    seriesName: 'Show',
    season: 1,
    episode: episode,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Ep $episode',
    id: id,
    overview: const OverviewModel(),
    parentId: 'series-1',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeasonModel _season({required int season, required int episodeCount, List<EpisodeModel> episodes = const []}) {
  return SeasonModel(
    parentImages: null,
    seasonName: 'Season $season',
    episodes: episodes,
    episodeCount: episodeCount,
    seriesId: 'series-1',
    season: season,
    seriesName: 'Show',
    name: 'Season $season',
    id: 'season-$season',
    overview: const OverviewModel(),
    parentId: 'series-1',
    playlistId: null,
    images: null,
    childCount: episodeCount,
    primaryRatio: null,
    userData: const UserData(),
    canDelete: false,
    canDownload: true,
  );
}

SeriesModel _series({
  EpisodeModel? selected,
  List<EpisodeModel>? episodes,
  List<SeasonModel>? seasons,
}) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: 'Show',
    id: 'series-1',
    playlistId: null,
    overview: const OverviewModel(),
    parentId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    selectedEpisode: selected,
    availableEpisodes: episodes,
    seasons: seasons,
  );
}

void main() {
  test('sushiSeriesDetailPlayTarget uses first episode on a fresh series', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep2 = _episode(id: 'ep-2', episode: 2);
    final series = _series(episodes: [ep1, ep2]);

    expect(sushiSeriesNeedsEpisodePick(series), isTrue);
    expect(sushiSeriesDetailPlayTarget(series)?.id, 'ep-1');
  });

  test('sushiSeriesDetailPlayTarget resumes in-progress episode', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep6 = _episode(id: 'ep-6', episode: 6).copyWith(
      season: 2,
      userData: const UserData(progress: 50),
    );
    final ep7 = _episode(id: 'ep-7', episode: 7).copyWith(season: 2);
    final series = _series(episodes: [ep1, ep6, ep7]);

    expect(sushiSeriesDetailPlayTarget(series)?.id, 'ep-6');
  });

  test('sushiSeriesDetailPlayTarget advances to next episode after watched', () {
    final ep6 = _episode(id: 'ep-6', episode: 6).copyWith(
      season: 2,
      userData: const UserData(played: true),
    );
    final ep7 = _episode(id: 'ep-7', episode: 7).copyWith(season: 2);
    final series = _series(episodes: [ep6, ep7]);

    expect(sushiSeriesDetailPlayTarget(series)?.id, 'ep-7');
  });

  test('sushiSeriesDetailPlayTarget ignores selected episode that is not next up', () {
    final ep1 = _episode(id: 'ep-1', episode: 1).copyWith(
      userData: const UserData(progress: 40),
    );
    final ep18 = _episode(id: 'ep-18', episode: 18);
    final series = _series(selected: ep18, episodes: [ep1, ep18]);

    expect(sushiSeriesDetailPlayTarget(series)?.id, 'ep-1');
  });

  test('sushiMarkPlayedItemId on a series is the play-target episode, not the series', () {
    final ep1 = _episode(id: 'sushi_ep_1', episode: 1);
    final ep2 = _episode(id: 'sushi_ep_2', episode: 2);
    final series = _series(episodes: [ep1, ep2]);

    expect(sushiMarkPlayedItemId(series), 'sushi_ep_1');
    expect(sushiMarkPlayedItemId(ep1), 'sushi_ep_1');
  });

  test('sushiMarkPlayedItemId advances after the current episode is watched', () {
    final ep1 = _episode(id: 'sushi_ep_1', episode: 1).copyWith(
      userData: const UserData(played: true),
    );
    final ep2 = _episode(id: 'sushi_ep_2', episode: 2);
    final series = _series(episodes: [ep1, ep2]);

    expect(sushiMarkPlayedItemId(series), 'sushi_ep_2');
  });

  test('sushiMarkPlayedItemId on a season is empty — never sushi_season_*', () {
    final season = _season(season: 1, episodeCount: 24);
    expect(sushiMarkPlayedItemId(season), '');
  });

  test('sushiSeriesPickerSeasons groups episodes by season', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep2 = _episode(id: 'ep-2', episode: 1).copyWith(season: 2);
    final series = _series(episodes: [ep1, ep2]);

    final seasons = sushiSeriesPickerSeasons(series);
    expect(seasons.length, 2);
    expect(seasons.first.seasonNumber, 1);
    expect(seasons.last.seasonNumber, 2);
  });

  test('sushiSeriesPickerSeasons omits seasons without playable episodes', () {
    final playable = _episode(id: 'ep-1', episode: 1);
    final missing = _episode(id: 'ep-2', episode: 1).copyWith(
      season: 2,
      location: ItemLocation.virtual,
    );
    final series = _series(episodes: [playable, missing]);

    final seasons = sushiSeriesPickerSeasons(series);
    expect(seasons.length, 1);
    expect(seasons.single.seasonNumber, 1);
  });

  test('sushiSeriesPickerSeasons uses season index even with empty episode lists', () {
    final series = _series(
      episodes: const [],
      seasons: [
        _season(season: 1, episodeCount: 12),
        _season(season: 2, episodeCount: 13),
      ],
    );

    final seasons = sushiSeriesPickerSeasons(series);
    expect(seasons.length, 2);
    expect(seasons.first.episodeCount, 12);
    expect(seasons.last.episodeCount, 13);
    expect(seasons.last.episodes, isEmpty);
  });
}
