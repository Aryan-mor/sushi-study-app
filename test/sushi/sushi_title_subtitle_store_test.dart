import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_title_subtitle_store.dart';

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

EpisodeModel _episode(String id, {required String parentId, required int episode}) => EpisodeModel(
      seriesName: 'Show',
      season: 1,
      episode: episode,
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('series episodes share one pick; a movie does not', () async {
    final ep1 = _episode('sushi_ep_1', parentId: 'sushi_tmdb_456', episode: 1);
    final ep2 = _episode('sushi_ep_2', parentId: 'sushi_tmdb_456', episode: 2);
    final other = _episode('sushi_ep_9', parentId: 'sushi_tmdb_999', episode: 1);
    final movie = _movie('sushi_tmdb_123');

    await sushiWriteTitleSubtitle(ep1, const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.ai));
    await sushiWriteTitleSubtitle(movie, const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.off));

    expect((await sushiReadTitleSubtitle(ep2))?.kind, SushiTitleSubtitleKind.ai);
    expect(await sushiReadTitleSubtitle(other), isNull);
    expect((await sushiReadTitleSubtitle(movie))?.kind, SushiTitleSubtitleKind.off);
  });

  test('manual track stores language and off clears it', () async {
    final movie = _movie('sushi_tmdb_7');
    await sushiRememberManualSubtitleTrack(
      movie,
      SubStreamModel(
        name: 'English',
        id: '2',
        title: 'English',
        displayTitle: 'English',
        language: 'en',
        codec: 'subrip',
        isDefault: false,
        isExternal: false,
        index: 2,
      ),
    );
    final saved = await sushiReadTitleSubtitle(movie);
    expect(saved?.kind, SushiTitleSubtitleKind.track);
    expect(saved?.language, 'en');

    await sushiRememberManualSubtitleTrack(movie, SubStreamModel.no());
    expect((await sushiReadTitleSubtitle(movie))?.kind, SushiTitleSubtitleKind.off);
  });

  test('a later manual pick replaces the earlier one', () async {
    final ep = _episode('sushi_ep_1', parentId: 'sushi_tmdb_456', episode: 1);
    await sushiWriteTitleSubtitle(ep, const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.ai));
    await sushiRememberManualSubtitleTrack(ep, SubStreamModel.no());
    expect((await sushiReadTitleSubtitle(ep))?.kind, SushiTitleSubtitleKind.off);

    final stale = sushiBeginManualSubtitleChoice();
    final current = sushiBeginManualSubtitleChoice();
    await sushiWriteTitleSubtitle(
      ep,
      const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.automatic),
      choiceGen: current,
    );
    await sushiWriteTitleSubtitle(
      ep,
      const SushiTitleSubtitleMemory(kind: SushiTitleSubtitleKind.ai),
      choiceGen: stale,
    );
    expect((await sushiReadTitleSubtitle(ep))?.kind, SushiTitleSubtitleKind.automatic);
  });
}
