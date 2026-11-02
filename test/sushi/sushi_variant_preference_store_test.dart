import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/sushi_variant_preference_store.dart';

MovieModel _movie(String id) => MovieModel(
      name: id,
      id: id,
      images: null,
      originalTitle: '',
      premiereDate: DateTime(2020),
      sortName: '',
      status: 'Released',
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      childCount: null,
      primaryRatio: 0.7,
      userData: const UserData(),
      canDelete: false,
      canDownload: false,
    );

EpisodeModel _episode(String id, {required String parentId}) => EpisodeModel(
      seriesName: 'Show',
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: parentId,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: 1.78,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDelete: false,
      canDownload: false,
    );

SeriesModel _series(String id) => SeriesModel(
      originalTitle: '',
      sortName: '',
      status: '',
      name: id,
      id: id,
      playlistId: null,
      overview: const OverviewModel(),
      parentId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('key derivation: movie, episode (keyed by series), series, unresolvable', () {
    expect(sushiVariantPreferenceKeyFor(_movie('sushi_tmdb_123')), 'movie:123');
    expect(sushiVariantPreferenceKeyFor(_episode('sushi_ep_9', parentId: 'sushi_tmdb_456')), 'series:456');
    expect(sushiVariantPreferenceKeyFor(_series('sushi_tmdb_456')), 'series:456');
    expect(sushiVariantPreferenceKeyFor(_movie('not_a_sushi_id')), isNull);
  });

  test('round-trips a written preference', () async {
    const pref = SushiMediaVariantPreference(qualityHeight: 1080, delivery: SushiStreamDelivery.hardSub);
    await sushiWriteVariantPreference('movie:123', pref);
    final loaded = await sushiReadVariantPreference('movie:123');
    expect(loaded?.qualityHeight, 1080);
    expect(loaded?.delivery, SushiStreamDelivery.hardSub);
  });

  test('different movies do not collide', () async {
    await sushiWriteVariantPreference('movie:1', const SushiMediaVariantPreference(qualityHeight: 720));
    await sushiWriteVariantPreference('movie:2', const SushiMediaVariantPreference(qualityHeight: 1080));
    expect((await sushiReadVariantPreference('movie:1'))?.qualityHeight, 720);
    expect((await sushiReadVariantPreference('movie:2'))?.qualityHeight, 1080);
  });

  test('unknown key reads as null', () async {
    expect(await sushiReadVariantPreference('movie:does_not_exist'), isNull);
  });
}
