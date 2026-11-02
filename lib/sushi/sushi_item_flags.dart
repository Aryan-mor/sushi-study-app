import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

class SushiItemFlags {
  const SushiItemFlags({
    this.favorite = false,
    this.watchLater = false,
    this.following = false,
  });
  final bool favorite;
  final bool watchLater;

  /// Series follow (ADR 0014 §D3) — meaningful only for series.
  final bool following;

  SushiItemFlags copyWith({bool? favorite, bool? watchLater, bool? following}) => SushiItemFlags(
        favorite: favorite ?? this.favorite,
        watchLater: watchLater ?? this.watchLater,
        following: following ?? this.following,
      );
}

final sushiItemFlagsProvider =
    StateNotifierProvider<SushiItemFlagsNotifier, Map<String, SushiItemFlags>>((ref) {
  return SushiItemFlagsNotifier();
});

class SushiItemFlagsNotifier extends StateNotifier<Map<String, SushiItemFlags>> {
  SushiItemFlagsNotifier() : super(const {});

  SushiItemFlags flagsFor(String id) => state[id] ?? const SushiItemFlags();

  Future<void> setFavorite(ItemBaseModel item, bool on) async {
    final tmdb = sushiTmdbIdFromItemId(item.id);
    if (tmdb == null) return;
    final kind = item is SeriesModel ? 2 : 1;
    state = {...state, item.id: flagsFor(item.id).copyWith(favorite: on)};
    await sushiSendFavEvent(tmdbId: tmdb, kind: kind, on: on);
  }

  Future<void> setWatchLater(ItemBaseModel item, bool on) async {
    final tmdb = sushiTmdbIdFromItemId(item.id);
    if (tmdb == null) return;
    final kind = item is SeriesModel ? 2 : 1;
    state = {...state, item.id: flagsFor(item.id).copyWith(watchLater: on)};
    await sushiSendLaterEvent(tmdbId: tmdb, kind: kind, on: on);
  }

  /// Toggle a series follow. No-op for a non-series item — follow is series-only (ADR 0014 §D3).
  Future<void> setFollowing(ItemBaseModel item, bool on) async {
    if (item is! SeriesModel) return;
    final tmdb = sushiTmdbIdFromItemId(item.id);
    if (tmdb == null) return;
    state = {...state, item.id: flagsFor(item.id).copyWith(following: on)};
    await sushiSendFollowEvent(tmdbId: tmdb, on: on);
  }
}
