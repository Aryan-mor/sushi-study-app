import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/view_model.dart';

/// Default home sidebar order when the user has not saved a custom order on the server.
const List<CollectionType> kDefaultHomeLibraryCollectionOrder = [
  CollectionType.movies,
  CollectionType.tvshows,
  CollectionType.playlists,
  CollectionType.music,
];

int _collectionTypeHomeRank(CollectionType t) {
  final i = kDefaultHomeLibraryCollectionOrder.indexOf(t);
  if (i >= 0) return i;
  return 100;
}

/// Movies → TV Shows → Playlists → Artists (music), then any other libraries.
List<ViewModel> applyDefaultHomeLibraryOrdering(List<ViewModel> views) {
  final copy = [...views];
  copy.sort((a, b) {
    final ra = _collectionTypeHomeRank(a.collectionType);
    final rb = _collectionTypeHomeRank(b.collectionType);
    if (ra != rb) return ra.compareTo(rb);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return copy;
}
