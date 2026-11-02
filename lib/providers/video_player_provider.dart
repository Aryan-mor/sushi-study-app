import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/sushi/sushi_playback_audio.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_title_subtitle_store.dart';
import 'package:fladder/sushi/sushi_audio_log.dart';
import 'package:collection/collection.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_iran_content.dart';
import 'package:fladder/sushi/sushi_memory_telemetry.dart';
import 'package:fladder/sushi/sushi_native_playback.dart';
import 'package:fladder/sushi/sushi_playback_repair.dart';
import 'package:fladder/sushi/sushi_stream_log.dart';
import 'package:fladder/sushi/sushi_playback_telemetry.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  // Warm player in background; [init] is serialized so a concurrent
  // [loadPlaybackItem] joins this future instead of double-creating mpv.
  unawaited(videoPlayer.init());
  return videoPlayer;
});

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];

  /// In-flight [init] — Dart is single-threaded so assigning before first await
  /// makes concurrent callers share one create/dispose cycle.
  Future<void>? _initFuture;

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  ProviderSubscription<VideoPlayerSettingsModel>? settingsChanged;
  @override
  void dispose() {
    settingsChanged?.close();
    super.dispose();
  }

  Future<void> init() {
    final inFlight = _initFuture;
    if (inFlight != null) {
      if (SushiEnv.isEnabled) {
        SushiStreamLog.event('video_player_init_join', fields: {
          'hasPlayer': state.hasPlayer,
        });
      }
      return inFlight;
    }

    late final Future<void> future;
    future = _initImpl().whenComplete(() {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    });
    _initFuture = future;
    return future;
  }

  Future<void> _initImpl() async {
    final settings = ref.read(videoPlayerSettingsProvider);
    if (state.hasPlayer && state.matchesSettings(settings)) {
      return;
    }

    // Reaching here tears the player down and rebuilds it — and on the native backend that also
    // finishes VideoPlayerActivity (NativePlayer.dispose -> disposeActivity), so it must stay rare.
    //
    // It used to run on EVERY play: MediaControlsWrapper.backend had no case for NativePlayer and
    // returned null, so matchesSettings could never be true there. The normal play path masked it
    // by calling openPlayer() afterwards, which launched a fresh Activity; the next-episode path
    // (PlaybackModelHelper.loadNewVideo) has no such call, so it was left waiting for an ExoPlayer
    // that never bound and the episode simply never started. See _activeBackend in
    // media_control_wrapper.dart. If this event ever starts firing per-play again, that comparison
    // is the first thing to check.
    SushiStreamLog.event('video_player_reinit', fields: {
      'hasPlayer': state.hasPlayer,
      'stack': StackTrace.current.toString().split('\n').take(8).join(' <- '),
    });

    await state.stop();
    await state.dispose();
    await state.init();

    for (final s in subscriptions) {
      s.cancel();
    }
    subscriptions.clear();

    settingsChanged = ref.listen(
      videoPlayerSettingsProvider,
      (previous, next) {
        final currentItem = ref.read(playBackModel)?.item;
        if (currentItem != null) {
          state.applyReplayGain(
            currentItem,
            settings: next,
          );
        }
      },
    );

    final subscription = state.stateStream.listen((value) {
      updateBuffering(value.buffering);
      updateBuffer(value.buffer);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
    });

    subscriptions.add(subscription);
  }

  Future<void> updateBuffering(bool event) async =>
      mediaState.update((state) => state.buffering == event ? state : state.copyWith(buffering: event));

  Future<void> updateBuffer(Duration buffer) async {
    mediaState.update(
      (state) => (state.buffer - buffer).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              buffer: buffer,
            ),
    );
  }

  Future<void> updateDuration(Duration duration) async {
    final catalog = ref.read(playBackModel)?.item.overview.runTime;
    if (duration == Duration.zero && catalog != null && catalog > Duration.zero) {
      duration = catalog;
    }
    mediaState.update((state) {
      return (state.duration - duration).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              duration: duration,
            );
    });
  }

  Future<void> updatePlaying(bool event) async {
    final currentState = playbackState;
    if (!state.hasPlayer || currentState.playing == event) return;
    if (currentState.state == VideoPlayerState.disposed) return;
    mediaState.update(
      (state) => state.copyWith(playing: event),
    );
    ref.read(playBackModel)?.updatePlaybackPosition(currentState.position, currentState.playing, ref);
  }

  Future<void> updatePosition(Duration event) async {
    if (!state.hasPlayer) return;
    if (playbackState.playing == false) return;
    final currentState = playbackState;
    if (currentState.state == VideoPlayerState.disposed) return;
    final currentPosition = currentState.position;

    if ((currentPosition - event).inSeconds.abs() < 1) return;

    final position = event;

    final lastPosition = currentState.lastPosition;
    final diff = (position.inMilliseconds - lastPosition.inMilliseconds).abs();

    final progressThreshold = SushiEnv.isEnabled ? const Duration(seconds: 30) : const Duration(seconds: 10);
    if (diff > progressThreshold.inMilliseconds) {
      mediaState.update((value) => value.copyWith(
            position: event,
            lastPosition: position,
          ));
      ref.read(playBackModel)?.updatePlaybackPosition(position, playbackState.playing, ref);
    } else {
      mediaState.update((value) => value.copyWith(
            position: event,
          ));
    }
  }

  Future<bool> loadPlaybackItem(
    PlaybackModel model,
    Duration startPosition, {
    // shouldReload() reopens the SAME video (new URL after an audio/quality
    // switch), not a fresh one — model.mediaStreams.defaultSubStreamIndex is
    // already the user's current, deliberate pick at that point. Re-running
    // sushiResolveSubtitleStreamIndex's "prefer Persian" default-selection
    // heuristic here would override that pick back to Persian on every such
    // reload, which is what made a manually chosen (non-Persian) subtitle keep
    // snapping back after switching audio tracks.
    bool preserveSelection = false,
  }) async {
    if (SushiEnv.isEnabled) {
      ref.read(sushiCatalogControllerProvider).cancelPrefetch();
      SushiStreamLog.event('player_load_start', fields: {
        'itemId': model.item.id,
        'hasMedia': model.media != null,
        'hasPlayer': state.hasPlayer,
      });
    }

    // Always await: joins provider warm-up init if still running (avoids double mpv create).
    await init();

    if (SushiEnv.isEnabled) {
      // Item id alone is not a unique playback session: picking a different file of the SAME
      // item from outside the player (e.g. another upload/quality of the same movie) keeps the
      // item id unchanged, so the AI/Automatic subtitle "active" marker from the previous file
      // would otherwise survive and show as on even though nothing was sideloaded onto this one.
      final sessionKey = '${model.item.id}|${model.mediaStreams?.currentVersionStream?.id ?? ''}';
      state.beginSushiSubtitleSession(sessionKey);
    }

    ref.read(playBackModel)?.dispose();
    await state.stop(leavingPlayer: false);
    ref.read(playbackRateProvider.notifier).state = 1.0;

    if (SushiEnv.isEnabled && sushiUsesNativePlayerRead(ref)) {
      SushiMemoryTelemetry.trimBeforeNativePlayback();
    }

    final useMinimizedPlayer =
        model.item.type == FladderItemType.audio || model.mediaStreams?.videoStreams.isEmpty == true;

    mediaState.update((state) => state.copyWith(
          state: useMinimizedPlayer ? VideoPlayerState.minimized : VideoPlayerState.fullScreen,
          fullScreen: !useMinimizedPlayer,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        ));

    final media = model.media;
    PlaybackModel? newPlaybackModel = model;
    final effectiveStartPosition = await model.resolvedStartPosition(startPosition);

    if (media != null) {
      SushiStreamLog.event('player_load', fields: {
        'itemId': model.item.id,
        'startPosition': SushiStreamLog.formatDuration(effectiveStartPosition),
        'startMs': effectiveStartPosition.inMilliseconds,
        'streamUrl': SushiStreamLog.describeUrl(media.url),
        'streamHost': SushiStreamLog.describeHost(media.url),
        // The queue drives the player's next/previous buttons (PlayableData.nextVideo /
        // previousVideo). A model that arrives here with queueLen=0 renders a player with no way
        // to reach the rest of the series, so it is worth seeing per load.
        'queueLen': model.playbackQueue.queue.length,
        'queueAnchor': model.playbackQueue.mainQueueCurrentId,
        'hasNext': model.nextVideo != null,
        'hasPrevious': model.previousVideo != null,
      });
      ref.read(playBackModel.notifier).update((state) => newPlaybackModel);
      SushiStartSubtitlePlan? startPlan;
      var replaySavedOnline = false;
      // Personal videos (ADR 0037) start with no subtitle plan: nothing is sniffed, searched or
      // translated, and the track stays Off.
      final personal = sushiIsPersonalPlayback(model);
      if (SushiEnv.isEnabled && !preserveSelection && !personal) {
        final saved = await sushiReadTitleSubtitle(model.item);
        if (saved != null) {
          startPlan = sushiPlanFromTitleSubtitleMemory(
            memory: saved,
            subStreams: model.subStreams,
          );
          replaySavedOnline = saved.kind == SushiTitleSubtitleKind.automatic;
        } else {
          startPlan = sushiPlanStartSubtitle(
            subStreams: model.subStreams,
            mediaSourceName: model.mediaStreams?.currentVersionStream?.name,
            isIranian: SushiIranContent.isIranian(
              tags: model.item.overview.tags,
              genres: model.item.overview.genreItems,
              name: model.item.name,
              mediaStreams: model.mediaStreams,
            ),
          );
        }
      }
      if (startPlan?.choice == SushiStartSubtitle.sniffEmbedded) {
        state.armEmbeddedSubtitleSniff();
      }
      await state.loadVideo(
        model,
        effectiveStartPosition,
        true,
        startSubtitlePlan: startPlan,
      );
      final settingsVolume = ref.read(videoPlayerSettingsProvider).volume;
      final backend = ref.read(videoPlayerSettingsProvider).wantedPlayer;
      SushiAudioLog.event('playback_load_volume', fields: {
        'backend': backend.name,
        'settingsVolume': settingsVolume,
        'defaultAudioIndex': model.mediaStreams?.defaultAudioStreamIndex,
        'audioStreamCount': model.audioStreams?.length,
        'audioIndexes': model.audioStreams?.map((s) => s.index).join(','),
        'resolvedAudioIndex': sushiResolvePlaybackAudioStream(model)?.index,
        'enablePlayPauseFade': ref.read(videoPlayerSettingsProvider).enablePlayPauseFade,
      });
      await state.setVolume(settingsVolume);

      final resolvedAudio = sushiResolvePlaybackAudioStream(model);
      await state.setAudioTrack(resolvedAudio, model);
      var resolvedSubIndex = personal
          ? -1
          : preserveSelection
              ? model.mediaStreams?.defaultSubStreamIndex
              : sushiResolveSubtitleStreamIndex(
                  selectedIndex: model.mediaStreams?.defaultSubStreamIndex,
                  serverDefaultIndex: model.mediaStreams?.defaultSubStreamIndex,
                  subStreams: model.subStreams,
                  mediaSourceName: model.mediaStreams?.currentVersionStream?.name,
                );
      if (startPlan != null) {
        resolvedSubIndex = startPlan.index;
      }
      final resolvedSub = resolvedSubIndex == -1
          ? (model.subStreams?.firstWhereOrNull((s) => s.index == -1) ?? SubStreamModel.no())
          : model.subStreams?.firstWhereOrNull((s) => s.index == resolvedSubIndex);
      // Route through PlaybackModel.setSubtitle (not state.setSubtitleTrack directly) so
      // mediaStreams.defaultSubStreamIndex reflects what auto-selection (e.g. preferred Persian
      // track) actually applied to the player — otherwise the subtitle picker UI keeps showing
      // "Off" as selected while a real subtitle is playing, since nothing ever wrote the resolved
      // index back onto the model the UI reads.
      final subtitleAppliedModel = await newPlaybackModel.setSubtitle(resolvedSub, state);
      if (subtitleAppliedModel != null) {
        newPlaybackModel = subtitleAppliedModel;
        ref.read(playBackModel.notifier).update((state) => newPlaybackModel);
      }

      final runtime = model.item.overview.runTime;
      final deferCatalogDuration = SushiEnv.isEnabled && sushiUsesNativePlayerRead(ref);
      ref.read(mediaPlaybackProvider.notifier).update((playback) {
        var next = playback.copyWith(
          state: useMinimizedPlayer ? VideoPlayerState.minimized : VideoPlayerState.fullScreen,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        );
        if (SushiEnv.isEnabled) {
          next = next.copyWith(
            position: effectiveStartPosition,
            lastPosition: effectiveStartPosition,
          );
          if (!deferCatalogDuration && runtime != null && runtime > Duration.zero) {
            next = next.copyWith(duration: runtime);
          }
        }
        return next;
      });

      await state.play();

      if (personal && !preserveSelection && !sushiUsesNativePlayerRead(ref)) {
        unawaited(_sushiShowPersonalEmbeddedSubs((model as SushiPlaybackModel).personalId!));
      }
      if (SushiEnv.isEnabled && !preserveSelection) {
        if (startPlan?.choice == SushiStartSubtitle.sniffEmbedded) {
          unawaited(state.awaitEmbeddedSniffThenMaybeOnline(model));
        } else if (startPlan?.choice == SushiStartSubtitle.automaticOnline) {
          unawaited(state.maybeSushiStartOnlineSubtitle(model, forced: replaySavedOnline));
        } else if (startPlan?.choice == SushiStartSubtitle.aiTranslate) {
          unawaited(state.maybeSushiStartAiSubtitle(model));
        }
      }
      if (SushiEnv.isEnabled) {
        SushiStreamRepairBridge.register(ref, newPlaybackModel);
        final runtime = model.item.overview.runTime;
        // Keep buffering=true until ExoPlayer reports STATE_READY — premature false
        // triggers stuck-repair loops during CDN resume seek (UI position already advanced).
        mediaState.update((state) {
          var next = state.copyWith(
            position: effectiveStartPosition,
            lastPosition: effectiveStartPosition,
          );
          if (!deferCatalogDuration && runtime != null) {
            next = next.copyWith(duration: runtime);
          }
          return next;
        });
      }

      return true;
    }

    mediaState.update((state) => state.copyWith(errorPlaying: true));
    unawaited(SushiPlaybackTelemetry.reportFailure(
      stage: 'player_load',
      reason: 'missing_media_url',
      itemId: model.item.id,
    ));
    return false;
  }

  Future<bool> loadAudioPlaybackItem(
    PlaybackModel model,
    List<ItemBaseModel> queue,
    int currentIndex,
    Duration startPosition,
  ) async {
    final currentPlayerState = ref.read(mediaPlaybackProvider).state;
    final keepFullScreenLayout = currentPlayerState == VideoPlayerState.fullScreen;
    final playbackSettings = ref.read(mediaPlaybackProvider);

    final initializedQueueState = PlaybackQueueState.fromQueue(
      queue,
      initialItemId: queue[currentIndex.clamp(0, queue.length - 1)].id,
      shuffleEnabled: playbackSettings.shuffleEnabled,
      repeatMode: playbackSettings.repeatMode,
    );
    final queuedModel = model.updatePlaybackQueue(initializedQueueState);
    final effectiveStartPosition = await queuedModel.resolvedStartPosition(startPosition);

    ref.read(playBackModel.notifier).update((state) => queuedModel);
    ref.read(playbackRateProvider.notifier).state = 1.0;

    mediaState.update((state) => state.copyWith(
          state: keepFullScreenLayout ? VideoPlayerState.fullScreen : VideoPlayerState.minimized,
          fullScreen: keepFullScreenLayout,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));

    await state.loadAudioQueue(queue, currentIndex, effectiveStartPosition, true);
    await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);

    mediaState.update((state) => state.copyWith(
          buffering: false,
          playing: true,
          position: effectiveStartPosition,
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));
    return true;
  }

  Future<void> reorderAudioQueueSection(
    AudioQueueSection section,
    int oldIndex,
    int newIndex,
  ) async {
    await state.reorderAudioQueueSection(section, oldIndex, newIndex);
  }

  /// A personal video's subtitle list comes from the file itself (ADR 0037): once MPV has listed
  /// its muxed tracks, offer them and turn the first one on. The person can switch it Off.
  Future<void> _sushiShowPersonalEmbeddedSubs(int personalId) async {
    final subs = await state.sushiEmbeddedSubStreams();
    if (subs.isEmpty || !mounted) return;
    bool stillPlaying(PlaybackModel? m) => m is SushiPlaybackModel && m.personalId == personalId;
    final current = ref.read(playBackModel);
    if (!stillPlaying(current)) return;
    final applied = await (current as SushiPlaybackModel).copyWith(embeddedSubs: subs).setSubtitle(subs.first, state);
    if (!mounted || !stillPlaying(ref.read(playBackModel))) return;
    ref.read(playBackModel.notifier).update((_) => applied);
  }

  Future<void> addToTemporaryQueue(List<ItemBaseModel> items) async {
    await state.addToTemporaryQueue(items);
  }

  Future<void> clearTemporaryQueue() async {
    state.clearTemporaryQueue();
  }

  Future<void> removeAudioQueueItem(ItemBaseModel item) async {
    await state.removeAudioQueueItem(item.id);
  }

  Future<void> removeAudioQueueSectionItem(
    AudioQueueSection section,
    int sectionIndex,
  ) async {
    await state.removeAudioQueueSectionItem(section, sectionIndex);
  }

  Future<void> playAudioQueueItem(ItemBaseModel item) async {
    if (ref.read(playBackModel) == null) return;
    await state.jumpToQueueItem(item);
  }

  Future<void> openPlayer(BuildContext context) async => state.openPlayer(context);

  Future<bool> takeScreenshot() async {
    final syncPath = ref.read(clientSettingsProvider).syncPath;
    // Early return here if we don't have a set/valid path. Skips actually taking the screenshot
    // which would be discarded.
    if (syncPath == null) {
      return false;
    }

    final screenshotsPath = p.join(syncPath, "Screenshots");
    final screenshotBuf = await state.takeScreenshot();

    if (screenshotBuf != null) {
      final savePathDirectory = Directory(screenshotsPath);

      // Should we try to create the directory instead?
      if (!await savePathDirectory.exists()) {
        return false;
      }

      final fileExtension = "png";
      final paddingAmount = 3;

      int maxNumber = 0;

      await for (var file in savePathDirectory.list()) {
        final finalSegment = file.uri.pathSegments.last;

        if (file is File && p.extension(finalSegment) == ".$fileExtension") {
          final match = RegExp(r'(\d+)').firstMatch(finalSegment);

          if (match != null) {
            final fileNumber = int.parse(match.group(0)!);

            if (fileNumber > maxNumber) {
              maxNumber = fileNumber;
            }
          }
        }
      }

      maxNumber += 1;

      final maxNumberStr = maxNumber.toString().padLeft(paddingAmount, '0');
      final screenshotName = '$maxNumberStr.$fileExtension';
      final screenshotPath = p.join(screenshotsPath, screenshotName);

      final screenshotFile = File(screenshotPath);
      await screenshotFile.writeAsBytes(screenshotBuf);

      return true;
    }

    return false;
  }
}
