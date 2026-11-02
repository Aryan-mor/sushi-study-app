import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';

/// Remote image URLs we may fetch for offline Synced posters. Rejects the fake
/// Jellyfin host built from `sushi://local` (`http://sushi/local/Items/.../Images/...`).
bool sushiImageUrlAllowed(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  if (uri.host.isEmpty || uri.host == 'sushi') return false;
  return true;
}

/// Jellyfin ticks are 100 ns. [Duration.inMicroseconds] * 10.
int sushiRunTimeTicks(Duration? duration) {
  if (duration == null || duration <= Duration.zero) return 0;
  return duration.inMicroseconds * 10;
}

/// Compact Jellyfin DTO so Fladder's SyncedItem data.json / SyncedScreen still work.
/// Bytes themselves come from Telegram, not this DTO.
BaseItemDto sushiItemToBaseItemDto(ItemBaseModel item, {SushiFile? file}) {
  final fileName = file != null ? sushiOfflineFileName(file.fileId) : (item.name.isEmpty ? 'video.mkv' : '${item.name}.mkv');
  final size = file?.sizeBytes ?? 0;
  final runtime = file != null && file.durationS > 0
      ? Duration(seconds: file.durationS)
      : item.overview.runTime;
  final kind = switch (item) {
    MovieModel _ => BaseItemKind.movie,
    SeriesModel _ => BaseItemKind.series,
    SeasonModel _ => BaseItemKind.season,
    EpisodeModel _ => BaseItemKind.episode,
    _ => item.jellyType ?? BaseItemKind.movie,
  };
  final episode = item is EpisodeModel ? item : null;
  final season = item is SeasonModel ? item : null;
  return BaseItemDto(
    id: item.id,
    name: item.name,
    originalTitle: item.name,
    sortName: item.name,
    type: kind,
    parentId: item.parentId,
    seriesId: episode?.parentId ?? season?.seriesId,
    seriesName: episode?.seriesName ?? season?.seriesName,
    seasonId: season?.id ?? (episode != null ? '${episode.parentId}_${episode.season}' : null),
    indexNumber: episode?.episode ?? season?.season,
    parentIndexNumber: episode?.season,
    overview: item.overview.summary,
    productionYear: item.overview.yearAired,
    premiereDate: item is MovieModel ? item.premiereDate : null,
    runTimeTicks: sushiRunTimeTicks(runtime),
    canDownload: true,
    canDelete: false,
    path: fileName,
    container: 'mkv',
    mediaSources: [
      MediaSourceInfo(
        id: file != null ? 'sushi_file_${file.fileId}' : item.id,
        path: fileName,
        size: size,
        container: 'mkv',
        name: (file?.displayName.trim().isNotEmpty ?? false) ? file!.displayName.trim() : (file?.qualityLabel ?? item.name),
        supportsDirectPlay: true,
        supportsDirectStream: true,
        runTimeTicks: sushiRunTimeTicks(runtime),
      ),
    ],
  );
}
