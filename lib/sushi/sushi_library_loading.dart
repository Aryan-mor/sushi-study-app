import 'package:fladder/providers/library_screen_provider.dart';

/// OX: no filter chips selected still loads/shows recommended shelves.
Set<LibraryViewType> sushiLibraryLoadTypes(LibraryScreenModel state) => libraryLoadTypes(state);

bool sushiShowLibraryRecommended(LibraryScreenModel state) {
  return state.viewType.isEmpty || state.viewType.contains(LibraryViewType.recommended);
}

bool sushiLibraryHasCachedContent(LibraryScreenModel state) {
  if (state.views.isEmpty || state.selectedViewModel == null) return false;
  final types = sushiLibraryLoadTypes(state);
  if (types.isEmpty) return false;
  if (types.contains(LibraryViewType.recommended) && state.recommendations.isNotEmpty) {
    return true;
  }
  if (types.contains(LibraryViewType.favourites) && state.favourites.isNotEmpty) {
    return true;
  }
  if (types.contains(LibraryViewType.genres) && state.genres.isNotEmpty) {
    return true;
  }
  return false;
}

bool sushiShowLibraryListSkeleton({
  required bool refreshing,
  required LibraryScreenModel state,
}) {
  return refreshing && !sushiLibraryHasCachedContent(state);
}
