import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/api_provider.dart';

part 'sushi_watchlist_dashboard.g.dart';

const _watchLaterPlaylistName = 'Watch Later';
const _dashboardLimit = 16;

bool _isWatchLaterPlaylistName(String? name) {
  final normalized = name?.trim().toLowerCase();
  return normalized == _watchLaterPlaylistName.toLowerCase() || normalized == 'watchlist';
}

class SushiWatchlistDashboardData {
  const SushiWatchlistDashboardData({
    this.playlistId,
    this.items = const [],
  });

  final String? playlistId;
  final List<ItemBaseModel> items;

  static const empty = SushiWatchlistDashboardData();
}

/// Watch Later rows parsed from GET /Users/{id}/Home/Feed (no extra HTTP on home).
final sushiWatchlistDashboardFeedProvider = StateProvider<SushiWatchlistDashboardData?>((ref) => null);

/// True after home feed (or fallback batch) applied watch-later data.
final sushiWatchlistFeedHandledProvider = StateProvider<bool>((ref) => false);

void sushiApplyWatchlistFromHomeFeedRef(Ref ref, SushiWatchlistDashboardData data) {
  ref.read(sushiWatchlistDashboardFeedProvider.notifier).state = data;
  ref.read(sushiWatchlistFeedHandledProvider.notifier).state = true;
}

void sushiResetWatchlistHomeFeed(WidgetRef ref) {
  ref.read(sushiWatchlistDashboardFeedProvider.notifier).state = null;
  ref.read(sushiWatchlistFeedHandledProvider.notifier).state = false;
}

void sushiResetWatchlistHomeFeedRef(Ref ref) {
  ref.read(sushiWatchlistDashboardFeedProvider.notifier).state = null;
  ref.read(sushiWatchlistFeedHandledProvider.notifier).state = false;
}

@riverpod
Future<SushiWatchlistDashboardData> sushiWatchlistDashboard(Ref ref) async {
  

  final api = ref.read(jellyApiProvider);
  final playlistsResponse = await api.usersUserIdItemsGet(
    recursive: true,
    includeItemTypes: [BaseItemKind.playlist],
  );
  final playlists = playlistsResponse.body?.items ?? const <BaseItemDto>[];
  BaseItemDto? watchLater;
  for (final playlist in playlists) {
    if (_isWatchLaterPlaylistName(playlist.name)) {
      watchLater = playlist;
      break;
    }
  }
  final playlistId = watchLater?.id;
  if (playlistId == null || playlistId.isEmpty) {
    return SushiWatchlistDashboardData.empty;
  }

  final itemsResponse = await api.playlistsPlaylistIdItemsGet(
    playlistId: playlistId,
    limit: _dashboardLimit,
    enableImageTypes: [
      ImageType.primary,
      ImageType.backdrop,
      ImageType.thumb,
    ],
    fields: [
      ItemFields.parentid,
      ItemFields.mediastreams,
      ItemFields.mediasources,
      ItemFields.candelete,
      ItemFields.candownload,
      ItemFields.primaryimageaspectratio,
      ItemFields.overview,
      ItemFields.childcount,
    ],
  );
  final items = itemsResponse.body?.items ?? const <ItemBaseModel>[];
  if (items.isEmpty) return SushiWatchlistDashboardData.empty;

  return SushiWatchlistDashboardData(playlistId: playlistId, items: items);
}
