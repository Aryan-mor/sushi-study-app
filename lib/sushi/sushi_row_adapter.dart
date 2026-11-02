import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/boxset_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';

const _sushiTmdbIdPrefix = 'sushi_tmdb_';
const _sushiPlaylistIdPrefix = 'sushi_playlist_';
const _sushiBoxsetIdPrefix = 'sushi_boxset_';

final _sushiTmdbSize = RegExp(r'/t/p/(w\d+|original)/');

/// TMDB CDN size token. Slider backdrops use [sushiTmdbSliderBackdropSize] (never `original`, R-META-8).
const sushiTmdbPosterSize = 'w500';
const sushiTmdbDetailSize = 'w780';
const sushiTmdbSliderBackdropSize = 'w1280';

ImageData? sushiTmdbImage(String strippedPath, {required String key, String size = sushiTmdbPosterSize, String extension = 'jpg'}) {
  if (strippedPath.isEmpty) return null;
  return ImageData(
    path: 'https://image.tmdb.org/t/p/$size/$strippedPath.$extension',
    key: key,
  );
}

/// Swap `/t/p/{size}/` on a TMDB CDN URL. Non-TMDB paths (Jellyfin fill query) stay untouched.
String sushiRewriteTmdbSize(String path, String size) {
  if (!_sushiTmdbSize.hasMatch(path)) return path;
  return path.replaceFirst(_sushiTmdbSize, '/t/p/$size/');
}

ImageData? sushiTmdbImageAtSize(ImageData? image, String size) {
  if (image == null || image.path.isEmpty) return image;
  final rewritten = sushiRewriteTmdbSize(image.path, size);
  if (rewritten == image.path) return image;
  return image.copyWith(path: rewritten, key: '${image.key}_$size');
}

/// Recovers the TMDB id from an id built by [sushiRowToItemBaseModel], or null if [itemId] isn't
/// one of ours — the reverse of that function's `'sushi_tmdb_$tmdbId'`, needed wherever a screen
/// only has the model's id and must ask `/item` for the rest (e.g. movies_details_provider.dart).
int? sushiTmdbIdFromItemId(String itemId) {
  if (!itemId.startsWith(_sushiTmdbIdPrefix)) return null;
  return int.tryParse(itemId.substring(_sushiTmdbIdPrefix.length));
}

int? sushiPlaylistIdFromItemId(String itemId) {
  if (!itemId.startsWith(_sushiPlaylistIdPrefix)) return null;
  return int.tryParse(itemId.substring(_sushiPlaylistIdPrefix.length));
}

/// Recovers the TMDB collection id from an id built by [sushiBoxsetMetaToItem], or null if
/// [itemId] isn't one of ours (mirrors [sushiPlaylistIdFromItemId]).
int? sushiBoxsetIdFromItemId(String itemId) {
  if (!itemId.startsWith(_sushiBoxsetIdPrefix)) return null;
  return int.tryParse(itemId.substring(_sushiBoxsetIdPrefix.length));
}

/// Maps one [SushiBoxsetMeta] card into a [BoxSetModel] carrying the collection's own identity
/// (name/poster/count), not a member movie's — the bug this adapter replaces (ADR 0009).
BoxSetModel sushiBoxsetMetaToItem(SushiBoxsetMeta meta) {
  return sushiBoxsetStub(
    collectionId: meta.collectionId,
    name: meta.name,
    poster: meta.poster,
    itemCount: meta.itemCount,
  );
}

BoxSetModel sushiBoxsetStub({
  required int collectionId,
  String name = '',
  String poster = '',
  int itemCount = 0,
}) {
  return BoxSetModel(
    name: name.isEmpty ? 'Collection' : name,
    id: '$_sushiBoxsetIdPrefix$collectionId',
    overview: const OverviewModel(),
    parentId: null,
    playlistId: null,
    images: ImagesData(
      primary: sushiTmdbImage(poster, key: '$_sushiBoxsetIdPrefix$collectionId'),
    ),
    childCount: itemCount == 0 ? null : itemCount,
    primaryRatio: 0.7,
    userData: const UserData(),
    canDelete: false,
    canDownload: false,
    jellyType: BaseItemKind.boxset,
  );
}

/// Compact-row lists have no episode/child counts. `childCount: 0` would make Fladder's
/// `hideEmptyShows` (default on) drop every poster, so leave it unknown.
PlaylistModel sushiPlaylistMetaToItem(SushiPlaylistMeta meta) {
  return sushiPlaylistStub(
    playlistId: meta.playlistId,
    name: meta.name,
    itemCount: meta.itemCount,
  );
}

PlaylistModel sushiPlaylistStub({
  required int playlistId,
  String name = '',
  int itemCount = 0,
}) {
  return PlaylistModel(
    name: name.isEmpty ? 'Playlist' : name,
    id: '$_sushiPlaylistIdPrefix$playlistId',
    overview: const OverviewModel(),
    parentId: null,
    playlistId: null,
    images: null,
    childCount: itemCount == 0 ? null : itemCount,
    primaryRatio: 0.8,
    userData: const UserData(),
    canDelete: false,
    canDownload: false,
    jellyType: BaseItemKind.playlist,
  );
}

/// Maps one Sushi compact [SushiRow] into the Jellyfin-shaped model Fladder's poster widgets
/// already render (ADR 0002: "adapt in Dart, not on the wire") — no `BaseItemDto` involved.
/// Follows the same direct-construction pattern `SeerrDashboardPosterModel.itemBaseModel`
/// (lib/models/seerr/seerr_dashboard_model.dart) uses for TMDB-only cards with no backing
/// Jellyfin item.
ItemBaseModel sushiRowToItemBaseModel(SushiRow row) {
  final id = '$_sushiTmdbIdPrefix${row.tmdbId}';

  final images = ImagesData(
    primary: row.poster.isEmpty
        ? null
        : ImageData(
            // catalog.proto Row.poster is stripped of its leading '/' and trailing '.jpg'.
            path: 'https://image.tmdb.org/t/p/w500/${row.poster}.jpg',
            key: id,
          ),
  );

  final overview = OverviewModel(
    yearAired: row.year == 0 ? null : row.year,
    communityRating: row.rating == 0 ? null : row.rating / 10,
  );

  if (row.kind == SushiKind.series) {
    return SeriesModel(
      name: row.title,
      id: id,
      images: images,
      originalTitle: row.title,
      sortName: row.title,
      status: 'Continuing',
      overview: overview,
      parentId: null,
      playlistId: null,
      childCount: null,
      primaryRatio: 0.7,
      userData: const UserData(),
      canDelete: false,
      canDownload: true,
      jellyType: BaseItemKind.series,
    );
  }

  return MovieModel(
    name: row.title,
    id: id,
    images: images,
    originalTitle: row.title,
    premiereDate: DateTime(row.year == 0 ? DateTime.now().year : row.year),
    sortName: row.title,
    status: 'Released',
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: const []),
    overview: overview,
    parentId: null,
    playlistId: null,
    childCount: null,
    primaryRatio: 0.7,
    userData: const UserData(),
    canDelete: false,
    canDownload: true,
    jellyType: BaseItemKind.movie,
  );
}
