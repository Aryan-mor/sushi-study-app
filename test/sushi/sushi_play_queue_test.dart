import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/sushi_play_default.dart';

EpisodeModel _ep({
  required String id,
  required int season,
  required int episode,
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
    parentId: 'sushi_tmdb_1396',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: 1.78,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: const []),
    canDelete: false,
    canDownload: true,
  );
}

void main() {
  test('mid-season episode does not fetch adjacent seasons', () {
    final season = [
      _ep(id: 'sushi_ep_1', season: 1, episode: 1),
      _ep(id: 'sushi_ep_2', season: 1, episode: 2),
      _ep(id: 'sushi_ep_3', season: 1, episode: 3),
    ];
    final adj = sushiEpisodeQueueAdjacentSeasons(
      currentSeason: season,
      playing: season[1],
    );
    expect(adj.previous, isFalse);
    expect(adj.next, isFalse);
  });

  test('last episode of a season fetches the next season', () {
    final season = [
      _ep(id: 'sushi_ep_1', season: 1, episode: 1),
      _ep(id: 'sushi_ep_2', season: 1, episode: 2),
    ];
    final adj = sushiEpisodeQueueAdjacentSeasons(
      currentSeason: season,
      playing: season.last,
    );
    expect(adj.previous, isFalse);
    expect(adj.next, isTrue);
  });

  test('first episode of season 2 fetches the previous season', () {
    final season = [
      _ep(id: 'sushi_ep_10', season: 2, episode: 1),
      _ep(id: 'sushi_ep_11', season: 2, episode: 2),
    ];
    final adj = sushiEpisodeQueueAdjacentSeasons(
      currentSeason: season,
      playing: season.first,
    );
    expect(adj.previous, isTrue);
    expect(adj.next, isFalse);
  });

  test('first episode of season 1 does not fetch season 0', () {
    final season = [
      _ep(id: 'sushi_ep_1', season: 1, episode: 1),
      _ep(id: 'sushi_ep_2', season: 1, episode: 2),
    ];
    final adj = sushiEpisodeQueueAdjacentSeasons(
      currentSeason: season,
      playing: season.first,
    );
    expect(adj.previous, isFalse);
    expect(adj.next, isFalse);
  });
}
