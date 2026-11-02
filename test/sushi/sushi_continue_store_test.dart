import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';

void main() {
  test('sushiPosterKeyFromImageUrl strips TMDB size path', () {
    expect(
      sushiPosterKeyFromImageUrl('https://image.tmdb.org/t/p/w500/abc123.jpg'),
      'abc123',
    );
    expect(sushiPosterKeyFromImageUrl(''), isEmpty);
  });

  test('continue identity uses TMDB id on a movie card', () {
    final movie = MovieModel(
      name: 'Tenet',
      id: 'sushi_tmdb_27205',
      images: ImagesData(primary: ImageData(path: 'https://image.tmdb.org/t/p/w500/tenet.jpg', key: 'k')),
      originalTitle: 'Tenet',
      premiereDate: DateTime(2020),
      sortName: 'Tenet',
      status: 'Released',
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      overview: const OverviewModel(yearAired: 2020, communityRating: 7.4),
      parentId: null,
      playlistId: null,
      childCount: null,
      primaryRatio: 0.7,
      userData: const UserData(),
      canDelete: false,
      canDownload: false,
    );
    final id = sushiContinueIdentity(movie);
    expect(id?.tmdbId, 27205);
    expect(id?.kind, SushiKind.movie);
    expect(id?.poster, 'tenet');
  });

  test('continue identity maps an episode onto its series', () {
    final ep = EpisodeModel(
      seriesName: 'Breaking Bad',
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: 'Pilot',
      id: 'sushi_ep_99',
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
      canDownload: false,
    );
    final id = sushiContinueIdentity(ep);
    expect(id?.tmdbId, 1396);
    expect(id?.kind, SushiKind.series);
    expect(id?.title, 'Breaking Bad');
  });

  test('continue json round-trips episode identity', () {
    const e = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 12 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_12',
      season: 1,
      episode: 12,
    );
    final parsed = SushiContinueEntry.fromJson(e.toJson());
    expect(parsed?.episodeItemId, 'sushi_ep_12');
    expect(parsed?.season, 1);
    expect(parsed?.episode, 12);
  });

  test('series continue toItem stays a series poster with progress', () {
    const e = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 12 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_12',
      season: 1,
      episode: 12,
    );
    final item = e.toItem();
    expect(item, isA<SeriesModel>());
    expect(item.userData.progress, closeTo(25, 0.1));
  });

  test('finished entries (>=90%) are not continue-watching', () {
    const e = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.movie,
      title: 'X',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 95 * 60 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 1,
    );
    expect(e.isFinished, isTrue);
    expect(e.isStarted, isTrue);
  });

  test('series bounce <5% keeps the in-progress episode', () {
    const existing = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 20 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_2',
      season: 1,
      episode: 2,
    );
    const bounce = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 10 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 2,
      episodeItemId: 'sushi_ep_1',
      season: 1,
      episode: 1,
    );
    final keep = sushiContinueRememberDecision(incoming: bounce, existing: existing);
    expect(keep?.episode, 2);
    expect(keep?.positionMs, existing.positionMs);
  });

  test('series finished with next episode stores next at 0%', () {
    const finished = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 46 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_2',
      season: 1,
      episode: 2,
    );
    const next = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 0,
      durationMs: 0,
      atMs: 2,
      episodeItemId: 'sushi_ep_3',
      season: 1,
      episode: 3,
    );
    final keep = sushiContinueRememberDecision(
      incoming: finished,
      existing: finished,
      nextEpisode: next,
    );
    expect(keep?.episode, 3);
    expect(keep?.positionMs, 0);
  });

  test('series finished with no next episode stays on the episode just finished', () {
    const finished = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 46 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_last',
      season: 5,
      episode: 16,
    );
    final keep = sushiContinueRememberDecision(incoming: finished, existing: finished);
    expect(keep?.season, 5);
    expect(keep?.episode, 16);
    expect(keep?.episodeItemId, 'sushi_ep_last');
    expect(keep?.positionMs, finished.positionMs);
  });

  test('movie bounce <5% still drops', () {
    const bounce = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.movie,
      title: 'X',
      year: 2020,
      rating: 80,
      poster: 'p',
      positionMs: 10 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 1,
    );
    expect(sushiContinueRememberDecision(incoming: bounce), isNull);
  });

  test('continue sort puts in-progress before rest, newest first inside each bucket', () {
    const midOld = SushiContinueEntry(
      tmdbId: 1,
      kind: SushiKind.movie,
      title: 'Mid old',
      year: 2020,
      rating: 80,
      poster: 'a',
      positionMs: 50 * 60 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 100,
    );
    const midNew = SushiContinueEntry(
      tmdbId: 2,
      kind: SushiKind.movie,
      title: 'Mid new',
      year: 2020,
      rating: 80,
      poster: 'b',
      positionMs: 40 * 60 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 200,
    );
    const restNew = SushiContinueEntry(
      tmdbId: 3,
      kind: SushiKind.series,
      title: 'Next ep',
      year: 2020,
      rating: 80,
      poster: 'c',
      positionMs: 0,
      durationMs: 0,
      atMs: 300,
      episode: 3,
    );
    const finished = SushiContinueEntry(
      tmdbId: 4,
      kind: SushiKind.movie,
      title: 'Done',
      year: 2020,
      rating: 80,
      poster: 'd',
      positionMs: 95 * 60 * 1000,
      durationMs: 100 * 60 * 1000,
      atMs: 400,
    );
    final sorted = sushiContinueSortEntries([finished, restNew, midOld, midNew]);
    expect(sorted.map((e) => e.tmdbId).toList(), [2, 1, 4, 3]);
  });

  test('series in-progress write keeps that episode', () {
    const incoming = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Breaking Bad',
      year: 2008,
      rating: 90,
      poster: 'bb',
      positionMs: 12 * 60 * 1000,
      durationMs: 48 * 60 * 1000,
      atMs: 1,
      episodeItemId: 'sushi_ep_2',
      season: 1,
      episode: 2,
    );
    final keep = sushiContinueRememberDecision(incoming: incoming);
    expect(keep?.episode, 2);
    expect(keep?.positionMs, incoming.positionMs);
  });

  test('series mid-watch with unknown duration is not finished', () {
    const incoming = SushiContinueEntry(
      tmdbId: 1396,
      kind: SushiKind.series,
      title: 'Ted Lasso',
      year: 2020,
      rating: 80,
      poster: 'tl',
      positionMs: 15 * 60 * 1000,
      durationMs: 0,
      atMs: 1,
      episodeItemId: 'sushi_ep_1',
      season: 1,
      episode: 1,
    );
    expect(incoming.isFinished, isFalse);
    final keep = sushiContinueRememberDecision(incoming: incoming);
    expect(keep?.episodeItemId, 'sushi_ep_1');
    expect(keep?.positionMs, incoming.positionMs);
  });
}
