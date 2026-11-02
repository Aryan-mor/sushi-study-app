import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/sushi_patch_playback_progress.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';
import 'package:fladder/util/refresh_after_watch_state.dart';

/// After playback ends, patch detail UserData immediately and refresh series/home.
///
/// [context.refreshData] after the player route often runs before [MediaControlWrapper.stop]
/// finishes its 1s delay and [playbackStopped] POST; listening for [playBackModel] → null
/// runs only after the server has been updated. Local patch uses the stop position already
/// known on [mediaPlaybackProvider] so the play button progress updates without a refetch race.
class SushiPlaybackDetailsRefresh extends ConsumerStatefulWidget {
  const SushiPlaybackDetailsRefresh({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SushiPlaybackDetailsRefresh> createState() => _SushiPlaybackDetailsRefreshState();
}

class _SushiPlaybackDetailsRefreshState extends ConsumerState<SushiPlaybackDetailsRefresh> {
  ProviderSubscription<PlaybackModel?>? _playbackSub;

  @override
  void initState() {
    super.initState();
    
    _playbackSub = ref.listenManual<PlaybackModel?>(
      playBackModel,
      (previous, next) {
        if (previous == null || next != null) return;
        final item = previous.item;
        // Sync read: stop() clears playBackModel before zeroing mediaPlayback.position.
        final media = ref.read(mediaPlaybackProvider);
        final position = media.position;
        final duration = media.duration;
        log('[sushi-progress] playBackModel→null item=${item.id} '
            'read position=$position duration=$duration');

        final runTime = sushiEffectiveRunTime(
          player: duration,
          catalog: item.overview.runTime,
        );
        sushiPatchDetailProvidersPlaybackProgress(
          ref,
          item: item,
          position: position,
          runTime: runTime,
        );

        final derived = sushiDerivePlaybackUserData(
          current: item.userData,
          position: position,
          runTime: runTime,
        );
        log('[sushi-progress] derived userData item=${item.id} runTime=$runTime '
            'progress=${derived.progress} played=${derived.played} '
            'ticks=${derived.playbackPositionTicks}');
        if (derived.played) {
          unawaited(ref.read(sushiCatalogItemFlagsProvider.notifier).setPlayed(item.id, true));
          unawaited(ref.read(userProvider.notifier).markAsPlayed(true, item.id));
        }

        unawaited((() async {
          // Prefs must land before fetchDetails paints from the continue store.
          await sushiContinueRemember(item, position, runTime, nextItem: previous.nextVideo);
          if (!mounted) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          await refreshAfterWatchStateChange(ref, item);
          if (!mounted) return;
          await sushiRefreshHomeAfterPlayback(ref);
        })());
      },
    );
  }

  @override
  void dispose() {
    _playbackSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
