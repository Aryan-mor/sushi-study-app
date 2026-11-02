import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/sushi/sushi_library_filters.dart';
import 'package:fladder/sushi/sushi_views.dart';

void main() {
  test('movie genres are TMDB names used in genreList, not TV compound names', () {
    expect(sushiFilterGenresForView(sushiViewMovies), contains('Science Fiction'));
    expect(sushiFilterGenresForView(sushiViewMovies), isNot(contains('Action & Adventure')));
    expect(sushiFilterGenresForView(sushiViewMovies), isNot(contains('Sci-Fi & Fantasy')));
  });

  test('series genres use TMDB TV names', () {
    expect(sushiFilterGenresForView(sushiViewSeries), contains('Action & Adventure'));
    expect(sushiFilterGenresForView(sushiViewSeries), contains('Sci-Fi & Fantasy'));
    expect(sushiFilterGenresForView(sushiViewSeries), isNot(contains('Science Fiction')));
  });

  test('boxsets playlists later have no catalog genre chips', () {
    expect(sushiViewSupportsCatalogFilters(sushiViewBoxsets), isFalse);
    expect(sushiFilterGenresForView(sushiViewBoxsets), isEmpty);
    expect(sushiFilterGenresForView(sushiViewPlaylists), isEmpty);
    expect(sushiFilterGenresForView(sushiViewLater), isEmpty);
  });

  test('favorites with no view still get the TMDB union', () {
    final genres = sushiFilterGenresForView('', favourites: true);
    expect(genres, contains('Science Fiction'));
    expect(genres, contains('Action & Adventure'));
  });

	test('years run newest-first from current year down to 1950', () {
    final years = sushiFilterYears(nowYear: 2026);
    expect(years.first, 2026);
    expect(years.last, 1950);
    expect(years, contains(1999));
  });

  test('movies and series default to release date descending', () {
    expect(sushiDefaultSortingOption(sushiViewMovies), SortingOptions.releaseDate);
    expect(sushiDefaultSortOrder(sushiViewMovies), SortingOrder.descending);
    expect(sushiDefaultSortingOption(sushiViewSeries), SortingOptions.releaseDate);
    expect(sushiDefaultSortOrder(sushiViewSeries), SortingOrder.descending);
  });

  test('boxsets playlists later keep A-Z', () {
    expect(sushiDefaultSortingOption(sushiViewBoxsets), SortingOptions.sortName);
    expect(sushiDefaultSortOrder(sushiViewBoxsets), SortingOrder.ascending);
    expect(sushiDefaultSortingOption(sushiViewPlaylists), SortingOptions.sortName);
    expect(sushiDefaultSortingOption(sushiViewLater), SortingOptions.sortName);
  });
}
