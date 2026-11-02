import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/sushi/sushi_views.dart';

/// TMDB movie genre names. Must match `detail.genreList` (docs/12) — jsonb `@>` is exact.
const sushiMovieGenres = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'History',
  'Horror',
  'Music',
  'Mystery',
  'Romance',
  'Science Fiction',
  'TV Movie',
  'Thriller',
  'War',
  'Western',
];

/// TMDB TV genre names. Same exact-match rule as [sushiMovieGenres].
const sushiTvGenres = [
  'Action & Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Kids',
  'Mystery',
  'News',
  'Reality',
  'Sci-Fi & Fantasy',
  'Soap',
  'Talk',
  'War & Politics',
  'Western',
];

const sushiFilterYearStart = 1950;

/// Genre/year SQL only exists on catalog movie/series `/list` (not flags, boxsets, playlists).
bool sushiViewSupportsCatalogFilters(String viewId) =>
    viewId == sushiViewMovies || viewId == sushiViewSeries;

/// Movies/Series default to premiere (series: newest episode), newest first. A-Z is a sort option.
bool sushiViewDefaultsToReleaseDate(String? viewId) =>
    viewId == sushiViewMovies || viewId == sushiViewSeries;

SortingOptions sushiDefaultSortingOption(String? viewId) =>
    sushiViewDefaultsToReleaseDate(viewId) ? SortingOptions.releaseDate : SortingOptions.sortName;

SortingOrder sushiDefaultSortOrder(String? viewId) =>
    sushiViewDefaultsToReleaseDate(viewId) ? SortingOrder.descending : SortingOrder.ascending;

List<String> sushiFilterGenresForView(String viewId, {bool favourites = false}) {
  if (viewId == sushiViewMovies) return sushiMovieGenres;
  if (viewId == sushiViewSeries) return sushiTvGenres;
  // Favorites page has no selected view; still show a genre picker (union of TMDB lists).
  if (favourites || viewId.isEmpty) {
    return {...sushiMovieGenres, ...sushiTvGenres}.toList()..sort();
  }
  return const [];
}

List<int> sushiFilterYears({int? nowYear, int start = sushiFilterYearStart}) {
  final end = nowYear ?? DateTime.now().year;
  if (end < start) return const [];
  return [for (var y = end; y >= start; y--) y];
}
