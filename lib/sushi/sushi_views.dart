import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/models/view_model.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';

const sushiViewMovies = 'sushi_view_movies';
const sushiViewSeries = 'sushi_view_series';
const sushiViewBoxsets = 'sushi_view_boxsets';
const sushiViewPlaylists = 'sushi_view_playlists';
const sushiViewLater = 'sushi_view_later';

ViewModel _sushiView({
  required String id,
  required String name,
  required CollectionType type,
}) {
  return ViewModel(
    name: name,
    id: id,
    serverId: 'sushi',
    dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
    canDelete: false,
    canDownload: false,
    parentId: '',
    collectionType: type,
    playAccess: dto.PlayAccess.full,
    recentlyAdded: const [],
    imageData: null,
    childCount: 0,
    path: null,
  );
}

/// Synthetic browse folders for Sushi drawer (ADR 0009). No personal Library hub.
List<ViewModel> sushiSyntheticViews() => [
      _sushiView(id: sushiViewMovies, name: 'Movies', type: CollectionType.movies),
      _sushiView(id: sushiViewSeries, name: 'Series', type: CollectionType.tvshows),
      _sushiView(id: sushiViewBoxsets, name: 'Box sets', type: CollectionType.boxsets),
      _sushiView(id: sushiViewPlaylists, name: 'Playlists', type: CollectionType.playlists),
    ];

/// Not part of [sushiSyntheticViews] (Watch later has no drawer entry there — it's reached via
/// the bottom-nav WatchLaterRoute), so callers that resolve a viewModelId to a view must check
/// for it separately or a lookup against the synthetic list alone will miss it.
ViewModel sushiWatchLaterView() => _sushiView(id: sushiViewLater, name: 'Watch later', type: CollectionType.movies);

SushiListScope? sushiScopeForViewId(String id, {bool favourites = false}) {
  if (favourites) return SushiListScope.favorites;
  return switch (id) {
    sushiViewMovies => SushiListScope.movies,
    sushiViewSeries => SushiListScope.series,
    sushiViewBoxsets => SushiListScope.boxsets,
    sushiViewPlaylists => SushiListScope.playlists,
    sushiViewLater => SushiListScope.later,
    _ => null,
  };
}

int sushiKindFromItemId(String itemId) {
  // SeriesModel vs MovieModel decided at decode; Row.kind is on wire. Default movie=1.
  // Callers that know the model should pass kind explicitly.
  return 1;
}
