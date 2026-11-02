import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/library_search_provider.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_views.dart';

SushiRow _row({required int tmdbId, required SushiKind kind, String title = 'Title'}) {
  return SushiRow(
    tmdbId: tmdbId,
    kind: kind,
    title: title,
    year: 1999,
    rating: 80,
    poster: 'abc',
  );
}

void main() {
  test('compact rows leave childCount unknown so hideEmptyShows cannot wipe the grid', () {
    final movie = sushiRowToItemBaseModel(_row(tmdbId: 1, kind: SushiKind.movie));
    final series = sushiRowToItemBaseModel(_row(tmdbId: 2, kind: SushiKind.series));

    expect(movie, isA<MovieModel>());
    expect(series, isA<SeriesModel>());
    expect(movie.canDownload, isTrue);
    expect(series.canDownload, isTrue);
    expect(movie.childCount, isNull);
    expect(series.childCount, isNull);

    final shown = [movie, series].hideEmptyChildren(true);
    expect(shown, hasLength(2));
  });

  test('childCount 0 is treated as empty and hidden', () {
    final hidden = sushiRowToItemBaseModel(_row(tmdbId: 3, kind: SushiKind.movie)).copyWith(childCount: 0);
    expect([hidden].hideEmptyChildren(true), isEmpty);
  });

  test('playlist meta maps to PlaylistModel with round-trip id', () {
    const meta = SushiPlaylistMeta(playlistId: 42, name: 'Weekend', itemCount: 3);
    final item = sushiPlaylistMetaToItem(meta);
    expect(item, isA<PlaylistModel>());
    expect(item.name, 'Weekend');
    expect(item.childCount, 3);
    expect(sushiPlaylistIdFromItemId(item.id), 42);
  });

  test('watch later is a home tab, not a drawer browse view', () {
    final ids = sushiSyntheticViews().map((v) => v.id).toList();
    expect(ids, isNot(contains(sushiViewLater)));
    expect(ids, contains(sushiViewMovies));
    expect(sushiScopeForViewId(sushiViewPlaylists), SushiListScope.playlists);
    expect(sushiScopeForViewId(sushiViewLater), SushiListScope.later);
  });

  test('TMDB size rewrite only touches /t/p/{size}/', () {
    expect(
      sushiRewriteTmdbSize('https://image.tmdb.org/t/p/w500/abc.jpg', sushiTmdbSliderBackdropSize),
      'https://image.tmdb.org/t/p/w1280/abc.jpg',
    );
    expect(
      sushiRewriteTmdbSize('https://jellyfin.example/Items/1/Images/Backdrop?fillWidth=2000', 'w1280'),
      'https://jellyfin.example/Items/1/Images/Backdrop?fillWidth=2000',
    );
  });
}
