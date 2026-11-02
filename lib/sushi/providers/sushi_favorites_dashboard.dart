import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';

class SushiFavoritesDashboardData {
  const SushiFavoritesDashboardData({this.items = const []});

  final List<ItemBaseModel> items;

  static const empty = SushiFavoritesDashboardData();
}

/// Favorites row parsed from GET /Users/{id}/Home/Feed (no extra HTTP on home).
final sushiFavoritesDashboardFeedProvider = StateProvider<SushiFavoritesDashboardData?>((ref) => null);

/// True after home feed applied favorites data.
final sushiFavoritesFeedHandledProvider = StateProvider<bool>((ref) => false);

void sushiApplyFavoritesFromHomeFeedRef(Ref ref, SushiFavoritesDashboardData data) {
  ref.read(sushiFavoritesDashboardFeedProvider.notifier).state = data;
  ref.read(sushiFavoritesFeedHandledProvider.notifier).state = true;
}

void sushiResetFavoritesHomeFeedRef(Ref ref) {
  ref.read(sushiFavoritesDashboardFeedProvider.notifier).state = null;
  ref.read(sushiFavoritesFeedHandledProvider.notifier).state = false;
}

/// No HTTP backend to fall back to — favorites come from the `/home` bot feed only.
final sushiFavoritesDashboardProvider = FutureProvider<SushiFavoritesDashboardData>((ref) async {
  return SushiFavoritesDashboardData.empty;
});
