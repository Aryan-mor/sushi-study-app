import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/sushi_season_watch_actions.dart';
import 'package:flutter_test/flutter_test.dart';

EpisodeModel _episode(String id, {ItemLocation location = ItemLocation.filesystem}) {
  return EpisodeModel(
    seriesName: 'Friends',
    season: 1,
    episode: 1,
    episodeEnd: null,
    location: location,
    name: 'E1',
    id: id,
    overview: const OverviewModel(),
    parentId: 'sushi_tmdb_1668',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: 1.78,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

void main() {
  test('season mark ids are sushi_ep_* catalog ids', () {
    final ids = sushiSeasonPlayedFlagIds([
      _episode('sushi_ep_591'),
      _episode('sushi_ep_592'),
    ]);
    expect(ids, ['sushi_ep_591', 'sushi_ep_592']);
  });

  test('season mark never emits sushi_season_* or continue stubs', () {
    final ids = sushiSeasonPlayedFlagIds([
      _episode('sushi_season_sushi_tmdb_1668_1'),
      _episode('sushi_ep_stub_sushi_tmdb_1668_1_1'),
      _episode('sushi_ep_591'),
    ]);
    expect(ids, ['sushi_ep_591']);
  });

  test('empty season list yields no fallback id', () {
    expect(sushiSeasonPlayedFlagIds(const []), isEmpty);
  });
}
