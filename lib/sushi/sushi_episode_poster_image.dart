import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';

/// Fladder uses blurOnly for unavailable episodes, which hides real images; OX supplies still art.
ImageData? sushiEpisodePosterImage(EpisodeModel episode, bool episodeAvailable) {
  if (episodeAvailable) return null;
  return episode.images?.primary ?? episode.parentImages?.primary;
}
