import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_series_watch_state.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeModel _episode({required String id, required int episode, int season = 1}) {
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
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeriesModel _series(List<EpisodeModel> episodes) {
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
  );
}

void main() {
  test('played flag on episode 1 advances nextUp to episode 2', () {
    final series = _series([
      _episode(id: 'sushi_ep_1', episode: 1),
      _episode(id: 'sushi_ep_2', episode: 2),
    ]);

    final painted = sushiPaintSeriesWatchState(
      series,
      playedIds: {'sushi_ep_1'},
    );

    expect(painted.availableEpisodes!.first.userData.played, isTrue);
    expect(painted.nextUp?.id, 'sushi_ep_2');
  });

  test('continue resume on episode 12 is nextUp even when earlier episodes are unwatched', () {
    final episodes = [
      for (var i = 1; i <= 12; i++) _episode(id: 'sushi_ep_$i', episode: i),
    ];
    const resume = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.series,
      title: 'Show',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_12',
      season: 1,
      episode: 12,
    );

    final painted = sushiPaintSeriesWatchState(
      _series(episodes),
      resume: resume,
    );

    expect(painted.nextUp?.id, 'sushi_ep_12');
    expect(painted.nextUp?.userData.progress, closeTo(25, 0.1));
  });

  test('played flag wins over resume progress on the same episode', () {
    final series = _series([
      _episode(id: 'sushi_ep_1', episode: 1),
      _episode(id: 'sushi_ep_2', episode: 2),
    ]);
    const resume = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.series,
      title: 'Show',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_1',
      season: 1,
      episode: 1,
    );

    final painted = sushiPaintSeriesWatchState(
      series,
      playedIds: {'sushi_ep_1'},
      resume: resume,
    );

    expect(painted.availableEpisodes!.first.userData.played, isTrue);
    expect(painted.availableEpisodes!.first.userData.progress, 0);
    expect(painted.nextUp?.id, 'sushi_ep_2');
  });

  test('sushiOverlayResumeOnEpisode restores continue position', () {
    const resume = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.series,
      title: 'Show',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 10 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_2',
      season: 1,
      episode: 2,
    );
    final painted = sushiOverlayResumeOnEpisode(_episode(id: 'sushi_ep_2', episode: 2), resume);
    expect(painted.userData.progress, closeTo(25, 0.1));
    expect(painted.userData.playbackPositionTicks, 10 * 60 * 1000 * 10000);
  });

  test('sushiOverlayResumeOnEpisode does not copy resume onto a different episode', () {
    const resume = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.series,
      title: 'Show',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 28 * 60 * 1000,
      durationMs: 40 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_13',
      season: 3,
      episode: 13,
    );
    final next = sushiOverlayResumeOnEpisode(_episode(id: 'sushi_ep_14', season: 3, episode: 14), resume);
    expect(next.userData.playbackPositionTicks, 0);
    expect(next.userData.progress, 0);
  });
}
