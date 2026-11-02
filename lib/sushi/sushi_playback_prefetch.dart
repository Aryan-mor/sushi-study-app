import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_provider_read.dart';

/// Sushi has its own `/play` delivery (docs/05), reached only from sushi_play_default.dart — the
/// Jellyfin PlaybackInfo warm-up this class used to do would just waste a blocked HTTP call
/// (api_provider.dart's JellyRequest guard, R-API-4) on every detail open for Sushi builds.
abstract final class SushiPlaybackPrefetch {
  static void scheduleForSeries(SushiRead read, SeriesModel? series, {bool once = false}) {}

  static void scheduleForMovie(SushiRead read, MovieModel? movie) {}

  static void scheduleForItem(
    SushiRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
    bool once = false,
  }) {}
}
