import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';

/// The three Sushi home rails (docs/12 §2), already adapted to Fladder's poster model. Rendered
/// directly by `dashboard_screen.dart` as their own `PosterRow`s — deliberately not `ViewModel`s,
/// since there's no Jellyfin folder behind them for "see all" to navigate to.
class SushiHomeRailsData {
  const SushiHomeRailsData({
    this.slider = const [],
    this.mostWatched = const [],
    this.trending = const [],
    this.seriesMostWatched = const [],
    this.seriesTrending = const [],
  });

  final List<ItemBaseModel> slider;
  final List<ItemBaseModel> mostWatched;
  final List<ItemBaseModel> trending;
  final List<ItemBaseModel> seriesMostWatched;
  final List<ItemBaseModel> seriesTrending;

  bool get hasAny =>
      slider.isNotEmpty ||
      mostWatched.isNotEmpty ||
      trending.isNotEmpty ||
      seriesMostWatched.isNotEmpty ||
      seriesTrending.isNotEmpty;

  static const empty = SushiHomeRailsData();
}

final sushiHomeRailsProvider = StateProvider<SushiHomeRailsData>((ref) => SushiHomeRailsData.empty);

void sushiApplySushiHomeRailsRef(Ref ref, SushiHomeRailsData data) {
  ref.read(sushiHomeRailsProvider.notifier).state = data;
}
