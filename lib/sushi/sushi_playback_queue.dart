import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_play_default.dart';

/// Fladder [PlaybackModelHelper.loadNewVideo] reuses [oldModel.playbackQueue] without
/// updating [PlaybackQueueState.mainQueueCurrentId], so after auto-next from ep1→ep2
/// the "next episode" anchor stays on ep1 and suggests ep2 again.
class SushiPlaybackModelHelper extends PlaybackModelHelper {
  const SushiPlaybackModelHelper({required super.ref});

  @override
  Future<PlaybackModel?> loadNewVideo(ItemBaseModel newItem) async {
    return _loadNewSushiVideo(newItem);
  }

  /// Sushi has no Jellyfin PlaybackInfo, so next/previous-episode navigation resolves the new
  /// file through Sushi's own `/play` delivery. The series queue is re-anchored on the new
  /// episode so the player's next/previous buttons keep working without another catalog fetch.
  Future<PlaybackModel?> _loadNewSushiVideo(ItemBaseModel newItem) async {
    final currentModel = ref.read(playBackModel);
    final media = ref.read(mediaPlaybackProvider);
    if (currentModel != null) {
      await sushiContinueRemember(
        currentModel.item,
        media.position,
        media.duration,
        nextItem: currentModel.nextVideo,
      );
    }
    ref.read(videoPlayerProvider).pause();
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: true));
    final preferHttpBridge =
        ref.read(videoPlayerSettingsProvider).wantedPlayer != PlayerOptions.nativePlayer;
    final newModel = await sushiBuildPlaybackModel(
      newItem,
      catalog: ref.read(sushiCatalogControllerProvider),
      preferHttpBridge: preferHttpBridge,
      sync: ref.read(syncProvider.notifier),
      playedIds: ref.read(sushiCatalogItemFlagsProvider).playedIds,
    );
    if (newModel == null) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: false));
      return null;
    }
    final PlaybackModel anchored;
    if (newModel.playbackQueue.queue.length > 1) {
      anchored = newModel;
    } else if (currentModel != null && currentModel.playbackQueue.queue.length > 1) {
      anchored = newModel.updatePlaybackQueue(currentModel.playbackQueue.jumpToItem(newItem.id));
    } else {
      anchored = newModel;
    }
    final start = await anchored.resolvedStartPosition();
    ref.read(videoPlayerProvider.notifier).loadPlaybackItem(anchored, start);
    return anchored;
  }
}

final sushiPlaybackModelHelper = Provider<PlaybackModelHelper>((ref) {
  return SushiPlaybackModelHelper(ref: ref);
});
