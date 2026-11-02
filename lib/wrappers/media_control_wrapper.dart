import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:audio_service/audio_service.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smtc_windows/smtc_windows.dart' if (dart.library.html) 'package:fladder/stubs/web/smtc_web.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/audio_prefetch_buffer.dart';
import 'package:fladder/models/playback/audio_url_resolver.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_iran_content.dart';
import 'package:fladder/sushi/subtitles/sushi_srt.dart';
import 'package:fladder/sushi/sushi_tdlib_bridge_controller.dart';
import 'package:fladder/sushi/sushi_tdlib_playback_resolver.dart';
import 'package:fladder/sushi/playback/sushi_persian_language.dart';
import 'package:fladder/sushi/sushi_playback_model.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_playback_subtitle.dart';
import 'package:fladder/sushi/sushi_title_subtitle_store.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/subtitle_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart' hide PlaybackState;
import 'package:fladder/sushi/subtitles/sushi_subtitle_actions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/lib_mdk.dart'
    if (dart.library.html) 'package:fladder/stubs/web/lib_mdk_web.dart';
import 'package:fladder/wrappers/players/lib_mpv.dart';
import 'package:fladder/wrappers/players/native_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

part 'audio_queue_handler.dart';

class MediaControlsWrapper extends BaseAudioHandler implements VideoPlayerControlsCallback {
  MediaControlsWrapper({required this.ref});

  BasePlayer? _player;
  BasePlayer? _previousPlayer;
  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  StreamSubscription<PlayerState>? _playerStateSubscription;
  Completer<String>? _embeddedSniff;
  final Set<String> _embeddedSniffCues = {};
  Timer? _embeddedSniffTimer;

  bool get hasPlayer => _player != null;

  /// The backend actually in use, including [NativePlayer].
  ///
  /// [backend] predates that player and reports null for it, which made [matchesSettings]
  /// permanently false on the native backend: every loadPlaybackItem then tore the player down and
  /// rebuilt it, and since NativePlayer.dispose() finishes the VideoPlayerActivity, every play
  /// destroyed and recreated the Activity + ExoPlayer. The normal play path hid this by calling
  /// openPlayer() afterwards; the queue path (next episode) does not, so it was left waiting for an
  /// ExoPlayer that never bound. Confirmed on an Android TV: reinit logged playerSame=true,
  /// playerRuntimeType=NativePlayer, backend=null, wantedPlayer=nativePlayer.
  ///
  /// Kept separate from the public [backend] rather than fixing that getter in place, because its
  /// null is load-bearing elsewhere — videoProfileProvider falls back to PlayerOptions.platformDefaults
  /// on null, so widening it would silently change the device profile sent to Jellyfin.
  PlayerOptions? get _activeBackend => switch (_player) {
        LibMPV _ => PlayerOptions.libMPV,
        LibMDK _ => PlayerOptions.libMDK,
        NativePlayer _ => PlayerOptions.nativePlayer,
        _ => null,
      };

  bool matchesSettings(VideoPlayerSettingsModel settings) {
    if (!hasPlayer || _activePlayerSettings == null) return false;
    return _activePlayerSettings!.playerSame(settings) && _activeBackend == settings.wantedPlayer;
  }

  PlayerOptions? get backend => switch (_player) {
        LibMPV _ => PlayerOptions.libMPV,
        LibMDK _ => PlayerOptions.libMDK,
        _ => null,
      };

  Stream<PlayerState> get stateStream => _stateController.stream;
  PlayerState? get lastState => _player?.lastState;

  Widget? subtitleWidget(bool showOverlay, {GlobalKey? controlsKey}) =>
      _player?.subtitles(showOverlay, controlsKey: controlsKey);
  Widget? videoWidget(Key key, BoxFit fit) => _player?.videoWidget(key, fit);

  final Ref ref;

  List<StreamSubscription> subscriptions = [];
  ProviderSubscription? _subtitleSettingsSubscription;
  SMTCWindows? smtc;

  bool initializedWrapper = false;
  VideoPlayerSettingsModel? _activePlayerSettings;
  bool _isNewPlayback = false;
  bool _isAudioQueueMode = false;
  bool _audioQueueTransitioning = false;
  bool _audioQueueCompletionPending = false;
  bool _isStopped = false;

  AudioPrefetchBuffer? _prefetchBuffer;
  List<ItemBaseModel> _mpvPlaylistItems = [];
  int _mpvPlaylistCurrentIndex = 0;
  StreamSubscription<int>? _playlistIndexSub;
  bool _syncingPlaylist = false;
  bool _syncPlaylistPending = false;
  bool _audioQueueRefillInProgress = false;
  bool _audioQueueSourceDepleted = false;
  int _audioQueueNextStartIndex = 0;

  Future<void> init() async {
    if (!initializedWrapper) {
      initializedWrapper = true;
      if (!kIsWeb && Platform.isAndroid) {
        VideoPlayerControlsCallback.setUp(this);
      }
      await AudioService.init(
        builder: () => this,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'nl.jknaapen.fladder.channel.playback',
          androidNotificationChannelName: 'Video playback',
          androidNotificationIcon: 'drawable/ic_notification',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          rewindInterval: Duration(seconds: 10),
          fastForwardInterval: Duration(seconds: 15),
          androidNotificationChannelDescription: "Playback",
          androidShowNotificationBadge: true,
        ),
      );
    }

    final player = switch (ref.read(videoPlayerSettingsProvider).wantedPlayer) {
      PlayerOptions.libMDK => LibMDK(),
      PlayerOptions.libMPV => LibMPV(),
      PlayerOptions.nativePlayer => NativePlayer(),
    };

    setup(player);
  }

  Future<void> dispose() async {
    log('[sushi-progress] MediaControlsWrapper.dispose() called — this path does NOT save progress '
        'playBackModel=${ref.read(playBackModel)?.item.id}');
    _subtitleSettingsSubscription?.close();
    await _playerStateSubscription?.cancel();
    _player?.dispose();
    _activePlayerSettings = null;
  }

  Future<void> setup(BasePlayer newPlayer) async {
    final oldPlayer = _player;
    if (oldPlayer != null && oldPlayer != newPlayer && _previousPlayer != oldPlayer) {
      await oldPlayer.dispose();
    }

    _player = newPlayer;
    final settings = ref.read(videoPlayerSettingsProvider);
    _activePlayerSettings = settings;
    await newPlayer.init(settings);
    _initPlayer();
    _subscribePlayerState();
  }

  void _initPlayer() {
    _subtitleSettingsSubscription?.close();
    for (var element in subscriptions) {
      element.cancel();
    }
    _subscribePlayer();
    _subtitleSettingsSubscription = ref.listen(subtitleSettingsProvider, (_, next) {
      _player?.applySubtitleSettings(next);
    });
  }

  void _subscribePlayerState() {
    _playerStateSubscription?.cancel();
    final player = _player;
    if (player == null) return;

    _playerStateSubscription = player.stateStream.listen((state) {
      if (!_stateController.isClosed) {
        _stateController.add(state);
      }
    });
  }

  Future<void> loadVideo(
    PlaybackModel model,
    Duration startPosition,
    bool play, {
    SushiStartSubtitlePlan? startSubtitlePlan,
  }) async {
    _isStopped = false;
    if (_player is LibMPV) {
      (_player as LibMPV).setMusicPlaybackMode(false);
    }
    final url = model.media?.url;
    if (sushiIsTdlibFileUrl(url)) {
      // Telegram-direct-play bytes only exist behind ExoPlayer's DataSource pipeline
      // (SushiRoutingDataSource/TelegramFileDataSource) — mpv/mdk can't resolve tdlib-file://
      // (it's not a protocol either of them understands, they just no-op), so this must run on
      // the native backend regardless of the user's player preference. Restored on the next
      // non-Telegram playback (see below).
      if (_player is! NativePlayer) {
        _previousPlayer ??= _player;
        await setup(NativePlayer());
      }
    } else if (_previousPlayer != null) {
      await _restorePreviousPlayer();
    }
    _bindEmbeddedCueListener();
    if (_player is NativePlayer) {
      final context = ref.read(localizationContextProvider);
      await (_player as NativePlayer).sendPlaybackDataToNative(
        context,
        model,
        startPosition,
        startSubtitlePlan: startSubtitlePlan,
      );
    }
    _isNewPlayback = play;
    await _player?.loadVideo(model.media?.url ?? "", play, startPosition: startPosition);
    _player?.applySubtitleSettings(ref.read(subtitleSettingsProvider));

    final context = ref.read(localizationContextProvider);
    if (context != null) {
      ref.read(windowTitleProvider.notifier).setPlayTitle(model.item.windowTitle(context.localized));
    }
  }

  Future<void> updateTVGuide(TVGuideModel guide) async {
    if (_player is NativePlayer) {
      (_player as NativePlayer).sendTVGuideModel(guide);
    }
  }

  Future<void> _restorePreviousPlayer() async {
    if (_previousPlayer == null) return;
    await setup(_previousPlayer!);
    _previousPlayer = null;
  }

  Future<void> openPlayer(BuildContext context) async {
    await _player?.open(context);
    // For the native Android player the VideoPlayerActivity runs as a separate
    // Activity and returns here when the user backs out (or the activity is
    // otherwise finished).  The Kotlin side has already stopped / released
    // ExoPlayer, but the Dart state is still marked as fullScreen and the
    // server has never received a playbackStopped notification.  Call stop()
    // now to (a) transition state → disposed, (b) disable wakelock, and
    // (c) report the final position to the Jellyfin API so that resume works.
    if (_player is NativePlayer) {
      await stop();
    }
  }

  Future<void> _updatePositionWithRetry(PlaybackModel model, Duration position, bool isPlaying) async {
    try {
      await model.updatePlaybackPosition(position, isPlaying, ref);
    } catch (error, stackTrace) {
      log('Failed to send playing: $isPlaying state to server. Retrying once. Error: $error\n$stackTrace');
      try {
        await Future.delayed(const Duration(milliseconds: 250));
        await model.updatePlaybackPosition(position, isPlaying, ref);
      } catch (retryError, retryStackTrace) {
        log('Retry failed for playing: $isPlaying state update. Error: $retryError\n$retryStackTrace');
      }
    }
  }

  void _subscribePlayer() {
    if (!kIsWeb && Platform.isWindows) {
      smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: true,
          nextEnabled: false,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: true,
          prevEnabled: false,
          stopEnabled: true,
        ),
      );

      if (smtc != null) {
        subscriptions.add(
          smtc!.buttonPressStream.listen((event) {
            switch (event) {
              case PressedButton.play:
                play();
                break;
              case PressedButton.pause:
                pause();
                break;
              case PressedButton.fastForward:
                fastForward();
                break;
              case PressedButton.rewind:
                rewind();
                break;
              case PressedButton.stop:
                stop();
                break;
              case PressedButton.previous:
                skipToPrevious();
                break;
              case PressedButton.next:
                skipToNext();
                break;
              case PressedButton.record:
                break;
              case PressedButton.channelUp:
                break;
              case PressedButton.channelDown:
                break;
            }
          }),
        );
      }
    }

    subscriptions.add(_player!.stateStream.listen(_updateStateStream));
  }

  Future<void> _updateStateStream(PlayerState value) async {
    if (_isStopped) return;

    if (value.completed && _isAudioQueueMode && !_audioQueueTransitioning && !_audioQueueCompletionPending) {
      _audioQueueCompletionPending = true;
      unawaited(_onAudioTrackCompleted().whenComplete(() => _audioQueueCompletionPending = false));
    } else if (value.completed && !_isAudioQueueMode && !_audioQueueTransitioning) {
      _onAudioTrackCompleted();
    }

    final keepForegroundAlive =
        value.playing || value.buffering || _audioQueueTransitioning || _audioQueueCompletionPending;

    playbackState.add(playbackState.value.copyWith(
      bufferedPosition: value.buffer,
      processingState: value.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
      updatePosition: value.position,
      playing: keepForegroundAlive,
    ));

    smtc?.setPosition(value.position);
    smtc?.setPlaybackStatus(keepForegroundAlive ? PlaybackStatus.playing : PlaybackStatus.paused);
  }

  @override
  Future<void> skipToNext() async {
    if (_isAudioQueueMode) {
      final wasRepeatOne = await _disableRepeatOneForSkip();
      if (!wasRepeatOne &&
          _player is LibMPV &&
          _isMpvPlaylistInSync() &&
          _mpvPlaylistItems.length > _mpvPlaylistCurrentIndex + 1) {
        final current = _mpvPlaylistItems[_mpvPlaylistCurrentIndex];
        final next = _mpvPlaylistItems[_mpvPlaylistCurrentIndex + 1];
        if (!_shouldCrossfade(current, next, manual: true)) {
          await (_player as LibMPV).playerNext();
          return;
        }
      }
      await _playNextQueueItem(manual: true);
      return;
    }
    return loadNextVideo();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_isAudioQueueMode) {
      if (_player?.lastState.position != null && _player!.lastState.position >= const Duration(seconds: 3)) {
        await _player?.seek(Duration.zero);
        return;
      }
      final wasRepeatOne = await _disableRepeatOneForSkip();
      if (!wasRepeatOne && _player is LibMPV && _isMpvPlaylistInSync() && _mpvPlaylistCurrentIndex > 0) {
        final current = _mpvPlaylistItems[_mpvPlaylistCurrentIndex];
        final previous = _mpvPlaylistItems[_mpvPlaylistCurrentIndex - 1];
        if (!_shouldCrossfade(current, previous, manual: true)) {
          await (_player as LibMPV).playerPrevious();
          return;
        }
      }
      await _playPreviousQueueItem();
      return;
    }
    return loadPreviousVideo();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    if (_isStopped) return;
    final position = _player?.lastState.position ?? Duration.zero;
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      updatePosition: position,
      controls: [MediaControl.play],
    ));
    await WakelockPlus.disable();
    final playerState = _player;
    if (playerState != null) {
      final model = ref.read(playBackModel);
      if (model != null) {
        await _updatePositionWithRetry(model, position, false);
        if (_isStopped) return;
        await _refreshMediaControls(model: model, playing: false);
      }
    }
    return super.pause();
  }

  @override
  Future<void> play() async {
    // Only enable wakelock for video; audio can continue with screen off
    final playBackItem = ref.read(playBackModel.select((value) => value?.item));
    if (playBackItem is! AudioModel) {
      await WakelockPlus.enable();
    }

    await _player?.play();
    if (_isStopped) return;

    final currentPosition = await ref.read(playBackModel.select((value) => value?.startDuration()));
    if (_isStopped) return;
    if (_isNewPlayback || !playbackState.value.playing) {
      _isNewPlayback = false;
      await ref.read(playBackModel)?.playbackStarted(currentPosition ?? Duration.zero, ref);
    }
    if (playBackItem == null) return;

    final playbackModel = ref.read(playBackModel);
    if (playbackModel != null) {
      await _refreshMediaControls(model: playbackModel, playing: true);
    }

    return super.play();
  }

  Future<void> _refreshMediaControls({PlaybackModel? model, required bool playing}) async {
    if (_isStopped) return;
    if (!ref.read(clientSettingsProvider).enableMediaKeys) return;
    final playbackModel = model ?? ref.read(playBackModel);
    if (playbackModel == null) return;

    final playBackItem = playbackModel.item;
    final poster =
        playBackItem.images?.primary ?? (playBackItem is ItemStreamModel ? playBackItem.parentImages?.primary : null);
    final currentPosition = _player?.lastState.position ?? await playbackModel.startDuration() ?? Duration.zero;
    if (_isStopped) return;

    windowSMTCSetup(playBackItem, currentPosition, playing);

    final hasNextVideo = ref.read(playBackModel.select((value) => value?.nextVideo != null));
    final hasPreviousVideo = ref.read(playBackModel.select((value) => value?.previousVideo != null));

    final queue = playbackModel.queue;
    final currentQueueIndex = queue.indexWhere((entry) => entry.id == playbackModel.item.id);
    final hasAudioQueue = queue.length > 1;
    final hasNextAudio = hasAudioQueue && (currentQueueIndex >= 0 ? currentQueueIndex < queue.length - 1 : true);
    final hasPreviousAudio = _isAudioQueueMode || (hasAudioQueue && (currentQueueIndex > 0 || currentQueueIndex == -1));

    final canSkipNext = hasNextVideo || hasNextAudio;
    final canSkipPrevious = hasPreviousVideo || hasPreviousAudio;

    final isMusic = playBackItem is AudioModel;

    mediaItem.add(MediaItem(
      id: playBackItem.id,
      title: playBackItem.title,
      rating: Rating.newHeartRating(playBackItem.userData.isFavourite),
      duration: playBackItem.overview.runTime ?? const Duration(seconds: 0),
      artUri: poster != null ? _imageDataToUri(poster.path) : null,
    ));
    playbackState.add(PlaybackState(
      playing: playing,
      updatePosition: currentPosition,
      bufferedPosition: _player?.lastState.buffer ?? playbackState.value.bufferedPosition,
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        if (canSkipNext) MediaControl.skipToNext,
        if (canSkipPrevious) MediaControl.skipToPrevious,
      ],
      systemActions: {
        if (canSkipNext) MediaAction.skipToNext,
        if (canSkipPrevious) MediaAction.skipToPrevious,
        MediaAction.seek,
        if (!isMusic) MediaAction.fastForward,
        MediaAction.setSpeed,
        if (!isMusic) MediaAction.rewind,
      },
      processingState:
          (_player?.lastState.buffering ?? false) ? AudioProcessingState.buffering : AudioProcessingState.ready,
    ));
  }

  Future<void> windowSMTCSetup(ItemBaseModel playBackItem, Duration currentPosition, bool playing) async {
    final mainContext = ref.read(localizationContextProvider);
    final poster =
        playBackItem.images?.primary ?? (playBackItem is ItemStreamModel ? playBackItem.parentImages?.primary : null);

    //Windows setup
    smtc?.updateMetadata(MusicMetadata(
      title: playBackItem.title,
      artist: mainContext != null ? playBackItem.label(mainContext.localized) : null,
      thumbnail: poster != null ? _imageDataToUri(poster.path).toString() : null,
    ));
    smtc?.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: (playBackItem.overview.runTime ?? const Duration(seconds: 0)).inMilliseconds,
        positionMs: currentPosition.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: (playBackItem.overview.runTime ?? const Duration(seconds: 0)).inMilliseconds,
      ),
    );

    smtc?.enableSmtc();
    smtc?.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused);
  }

  /// audio_service calls this when Android reports the media notification gone, and its default
  /// implementation is [stop] — correct for the case it documents, the user swiping the
  /// notification away.
  ///
  /// It also fires when the notification merely disappears, which happens on every episode change:
  /// [SushiPlaybackModelHelper.loadNewVideo] pauses first, and with `androidStopForegroundOnPause` the
  /// pause removes the foreground notification. The callback then lands ~1.5s later, by which time
  /// the NEXT episode is already loaded, and [stop] operates on it. Measured on a TV, two of these
  /// arrived per transition and the first one cleared the episode that had just started — which
  /// wiped the native playbackData (no title, and prev/next drawn at CustomButton's disabled alpha
  /// of 0.15, i.e. invisible), reported a spurious "stopped at 0s" to Jellyfin for an episode
  /// seconds old, and nulled playBackModel so nothing reported that episode's progress afterwards.
  ///
  /// A video session is never torn down from here: it has explicit exits (Back, the close button,
  /// Activity finish) that all call [stop] with the right item. Audio keeps the documented
  /// behaviour, where the notification is a real control surface the user can reach.
  @override
  Future<void> onNotificationDeleted() async {
    final model = ref.read(playBackModel);
    if (model != null && model.item.type != FladderItemType.audio) return;
    return super.onNotificationDeleted();
  }

  @override
  Future<void> stop({bool leavingPlayer = true}) async {
    if (_isStopped) return;
    _isStopped = true;

    if (_player is LibMPV) {
      (_player as LibMPV).setMusicPlaybackMode(false);
    }

    smtc?.setPlaybackStatus(PlaybackStatus.stopped);
    smtc?.clearMetadata();
    smtc?.disableSmtc();
    mediaItem.value = null;
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.completed,
        controls: [],
      ),
    );

    final playbackModel = ref.read(playBackModel);
    log('[sushi-progress] stop() entered playbackModel=${playbackModel == null ? "NULL (early return, nothing will be saved)" : playbackModel.item.id}');
    if (playbackModel == null) {
      if (leavingPlayer) _resumeCatalogPrefetch();
      return;
    }

    // mpv/mdk path only: ExoPlayer's own Activity teardown closes its session natively
    // (VideoPlayerImplementation.clearSession) — this player runs inside the normal Flutter
    // widget tree instead, so nothing else calls this. No-op for any non-Telegram url.
    //
    // tdlib-file:// must NOT be added here as "defence in depth", however tempting: this reads the
    // CURRENT playbackModel, and openPlayer() calls stop() when the previous VideoPlayerActivity
    // finishes — which on the next-episode path is after the new episode's model is already in
    // place. Including it therefore reported the incoming session as ended and killed the playback
    // that was starting. Measured on a TV: the release landed ~0.5s after the new session was
    // minted, and the episode never opened.
    final sessionUrl = playbackModel.media?.url;
    if (sushiIsTelegramDirectPlayUrl(sessionUrl)) {
      unawaited(SushiTdlibBridgeController.instance().stopPlaybackSession(sessionUrl!));
    }

    final media = ref.read(mediaPlaybackProvider);
    var position = _player?.lastState.position ?? Duration.zero;
    var totalDuration = _player?.lastState.duration ?? Duration.zero;
    if (position <= Duration.zero && media.position > Duration.zero) {
      position = media.position;
    }
    if (totalDuration <= Duration.zero && media.duration > Duration.zero) {
      totalDuration = media.duration;
    }

    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.disposed));
    WakelockPlus.disable();
    _player?.stop();
    ref.read(windowTitleProvider.notifier).setPlayTitle(null);

    log('[sushi-progress] stop() captured item=${playbackModel.item.id} '
        'position=$position totalDuration=$totalDuration '
        'mediaPlaybackProvider.position=${media.position}');

    // Small delay so we don't post right after playback/progress update
    await Future.delayed(const Duration(seconds: 1));

    await playbackModel.playbackStopped(position, totalDuration, ref);
    ref.read(playBackModel.notifier).update((_) => null);
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: Duration.zero));

    if (_isAudioQueueMode) {
      _isAudioQueueMode = false;
      _playlistIndexSub?.cancel();
      _playlistIndexSub = null;
      _prefetchBuffer?.invalidate();
      _prefetchBuffer = null;
      _mpvPlaylistItems = [];
      _mpvPlaylistCurrentIndex = 0;
      _syncingPlaylist = false;
      _syncPlaylistPending = false;
      await _restorePreviousPlayer();
    }

    if (leavingPlayer) _resumeCatalogPrefetch();
    return super.stop();
  }

  void _resumeCatalogPrefetch() {
    if (!SushiEnv.isEnabled) return;
    ref.read(sushiCatalogControllerProvider).resumePrefetch();
  }

  Future<void> playOrPause() async {
    await _player?.playOrPause();
    if (_isStopped) return;
    final playing = _player?.lastState.playing ?? false;
    final position = _player?.lastState.position ?? Duration.zero;
    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      updatePosition: position,
      controls: [playing ? MediaControl.pause : MediaControl.play],
    ));

    if (playing) {
      // Only enable wakelock for video; audio can continue with screen off
      final playBackItem = ref.read(playBackModel.select((value) => value?.item));
      if (playBackItem is! AudioModel) {
        await WakelockPlus.enable();
      }
    } else {
      await WakelockPlus.disable();
    }

    final playerState = _player;
    if (playerState != null) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: position));

      final model = ref.read(playBackModel);
      if (model != null) {
        await _updatePositionWithRetry(model, position, playerState.lastState.playing);
        if (_isStopped) return;
        await _refreshMediaControls(model: model, playing: playing);
      }
    }
  }

  Uri _imageDataToUri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.file(path);
  }

  bool _isMpvPlaylistInSync() {
    final playbackModel = ref.read(playBackModel);
    if (playbackModel == null) return false;
    if (_mpvPlaylistItems.isEmpty) return false;
    if (_mpvPlaylistCurrentIndex < 0 || _mpvPlaylistCurrentIndex >= _mpvPlaylistItems.length) return false;
    return _mpvPlaylistItems[_mpvPlaylistCurrentIndex].id == playbackModel.item.id;
  }

  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async =>
      await _player?.setAudioTrack(model, playbackModel) ?? -1;

  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async =>
      await _player?.setSubtitleTrack(model, playbackModel) ?? -1;

  /// A personal video's own muxed subtitle tracks (ADR 0037). Only MPV lists them here; the native
  /// player lists them in its own picker, and other backends get none.
  Future<List<SubStreamModel>> sushiEmbeddedSubStreams() async {
    final player = _player;
    if (player is! LibMPV) return const [];
    return player.sushiEmbeddedSubStreams();
  }

  /// Sushi Automatic / Online / Translate: inject SRT.
  /// Native VideoPlayerActivity is a separate Exo surface. Dart `_player` is often
  /// still LibMPV — do not also load into mpv (it dumps the whole SRT into logcat).
  /// Returns whether the subtitle was actually applied. Only the native-Exo pigeon
  /// path can observe a real failure (missing media item/activity) — the Dart-side
  /// players have no failure signal to report, so they're assumed to have succeeded
  /// once the underlying call returns.
  Future<bool> setSubtitleFromText(String data, {String? title, String? language}) async {
    data = sushiNormalizeSubtitleText(data);
    if (nativeActivityStarted) {
      if (_player is NativePlayer) {
        await _player?.setSubtitleFromText(data, title: title, language: language);
        return true;
      } else {
        final ok = await VideoPlayerApi().setSubtitleFromText(data, title, language);
        log(
          'sushi_sub_from_text native_exo chars=${data.length} ok=$ok',
          name: 'sushi.subs',
        );
        return ok;
      }
    }
    await _player?.setSubtitleFromText(data, title: title, language: language);
    return true;
  }

  Future<void> setVolume(double volume) async => _player?.setVolume(volume);

  @override
  Future<void> seek(Duration position) {
    final model = ref.read(playBackModel);
    if (kIsWeb && _isRemuxStreamUrl(model?.media?.url) && model != null) {
      // Progressive remux (sushi-stream stream.ts) has no random access; the browser can only
      // play forward from ?start=. Re-request the stream from the target position instead of
      // asking the player to seek (which silently fails or stalls).
      ref.read(mediaPlaybackProvider.notifier).update(
            (state) => state.copyWith(position: position, buffering: true),
          );
      unawaited(ref.read(playbackModelHelper).shouldReload(model));
      return super.seek(position);
    }
    _player?.seek(position);
    if (_player?.lastState.playing == false) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: position));
    }
    return super.seek(position);
  }

  static bool _isRemuxStreamUrl(String? url) =>
      url != null && (url.contains('/stream.ts') || url.contains('stream.ts?'));

  @override
  Future<void> setSpeed(double speed) {
    _player?.setSpeed(speed);
    return super.setSpeed(speed);
  }

  //Native player calls
  @override
  Future<void> loadNextVideo() async {
    final nextVideo = ref.read(playBackModel.select((value) => value?.nextVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    if (nextVideo != null && !buffering) ref.read(playbackModelHelper).loadNewVideo(nextVideo);
  }

  @override
  Future<void> loadPreviousVideo() async {
    final previousVideo = ref.read(playBackModel.select((value) => value?.previousVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    if (previousVideo != null && !buffering) ref.read(playbackModelHelper).loadNewVideo(previousVideo);
  }

  @override
  void onStop() => stop();

  /// Belt-and-suspenders fallback for the native (ExoPlayer/Telegram) player path. [onStop]
  /// above crosses from the native VideoPlayerActivity back into this long-lived engine via a
  /// Pigeon call from a Compose onDispose — observed on a real device to silently never arrive
  /// (no log, no crash, no saved progress). The native side's clearSession() runs reliably on
  /// every teardown regardless, and now calls this with the last known position/duration as a
  /// second chance. If [onStop] already ran, playBackModel is already null and this is a no-op.
  @override
  void onPlaybackClosed(int positionMs, int durationMs) {
    final playbackModel = ref.read(playBackModel);
    log('[sushi-progress] onPlaybackClosed(positionMs=$positionMs, durationMs=$durationMs) '
        'playBackModel=${playbackModel == null ? "already null — onStop() already handled this" : playbackModel.item.id}');
    if (playbackModel == null) return;

    log('[sushi-progress] onPlaybackClosed: onStop() did not run — saving progress from native-reported values now');
    ref.read(mediaPlaybackProvider.notifier).update(
          (state) => state.copyWith(
            position: Duration(milliseconds: positionMs),
            duration: durationMs > 0 ? Duration(milliseconds: durationMs) : state.duration,
            state: VideoPlayerState.disposed,
          ),
        );
    // Nulling playBackModel here is what SushiPlaybackDetailsRefresh listens for — it reads
    // mediaPlaybackProvider (just updated above) and runs the same patch/persist/refresh
    // pipeline that a normal stop() triggers, so this reuses that logic rather than duplicating it.
    ref.read(playBackModel.notifier).update((_) => null);
  }

  @override
  void swapAudioTrack(int value) async {
    final playbackModel = ref.read(playBackModel);
    final newModel = await playbackModel?.setAudio(
        playbackModel.audioStreams?.firstWhere((element) => element.index == value), this);
    ref.read(playBackModel.notifier).update((state) => newModel);
    // Sushi already switched the muxed track directly on the player (same file, same URL — no
    // server-side renegotiation needed). shouldReload() re-fetches PlaybackInfo and rebuilds the
    // model from whatever that endpoint reports, which for Sushi items is not the rich per-track
    // catalog data sushiBuildMediaStreams already produced — it silently collapsed the audio/
    // subtitle picker down to a single "Default" entry after every track switch.
    if (newModel != null && !SushiEnv.isEnabled) {
      await ref.read(playbackModelHelper).shouldReload(newModel);
    }
  }

  @override
  void swapSubtitleTrack(int value) async {
    final playbackModel = ref.read(playBackModel);
    final track = playbackModel?.subStreams?.firstWhereOrNull((element) => element.index == value);
    final newModel = await playbackModel?.setSubtitle(track, this);
    ref.read(playBackModel.notifier).update((state) => newModel);
    if (SushiEnv.isEnabled && playbackModel != null) {
      unawaited(sushiRememberManualSubtitleTrack(playbackModel.item, track));
    }
    // See swapAudioTrack above — same reasoning, Sushi already applied the switch natively.
    if (newModel != null && !SushiEnv.isEnabled) {
      await ref.read(playbackModelHelper).shouldReload(newModel);
    }
  }

  @override
  Future<void> loadProgram(GuideChannel selection) async {
    final channelId = selection.channelId;
    final model = await ref.read(liveTvProvider.notifier).fetchDashboard();
    final channel = model.channels.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null) {
      await ref.read(playbackModelHelper).loadTVChannel(channel);
    }
  }

  @override
  Future<List<GuideProgram>> fetchProgramsForChannel(String channelId) async {
    final channel =
        (await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: channelId)).body as ChannelModel;

    final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(channel);

    final context = ref.read(localizationContextProvider);

    return programs
        .map((p) => GuideProgram(
              id: p.id,
              channelId: channelId,
              name: p.name,
              startMs: p.startDate.millisecondsSinceEpoch,
              endMs: p.endDate.millisecondsSinceEpoch,
              primaryPoster: p.images?.primary?.path,
              overview: p.overview,
              subTitle: context != null ? p.subLabel(context.localized) : null,
            ))
        .toList();
  }

  @override
  Future<List<SushiOnlineSubtitlePack>> searchSushiOnlineSubtitles() async {
    try {
      final packs = await sushiSearchOnlinePacks(ref);
      return [
        for (final p in packs)
          SushiOnlineSubtitlePack(
            tag: p.tag,
            title: p.title,
            hint: p.hint.isEmpty ? p.title : p.hint,
          ),
      ];
    } catch (e) {
      log('searchSushiOnlineSubtitles: $e');
      return const [];
    }
  }

  @override
  Future<SushiSubtitleActionResult> downloadSushiOnlineSubtitle(String tag, String fileName) async {
    final r = await sushiDownloadOnlinePack(src: ref, tag: tag, fileName: fileName, player: this);
    return SushiSubtitleActionResult(
      ok: r.ok,
      errorCode: r.errorCode,
      label: r.label,
      fileNames: r.fileNames,
      tag: r.tag,
    );
  }

  @override
  Future<SushiSubtitleActionResult> autoLoadSushiSubtitle() async {
    final r = await sushiRunAutoLoad(ref, player: this, remember: true);
    return SushiSubtitleActionResult(
      ok: r.ok,
      errorCode: r.errorCode,
      label: r.label,
      fileNames: r.fileNames,
      tag: r.tag,
    );
  }

  void beginSushiSubtitleSession(String sessionKey) {
    sushiBeginPlaybackSubtitleSession(ref, sessionKey);
  }

  void armEmbeddedSubtitleSniff() {
    _openEmbeddedSniffWindow(const Duration(seconds: 4));
  }

  void _openEmbeddedSniffWindow(Duration window) {
    final pending = _embeddedSniff;
    _embeddedSniffTimer?.cancel();
    _embeddedSniffTimer = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(_embeddedSniffCues.join('\n'));
    }
    _embeddedSniffCues.clear();
    _embeddedSniff = Completer<String>();
    _bindEmbeddedCueListener();
    _embeddedSniffTimer = Timer(window, _finishEmbeddedSniff);
  }

  void _bindEmbeddedCueListener() {
    if (_embeddedSniff == null || _embeddedSniff!.isCompleted) return;
    void onCue(String text) => _noteEmbeddedCue(text);
    final player = _player;
    if (player is LibMPV) player.embeddedCueListener = onCue;
    if (player is NativePlayer) player.embeddedCueListener = onCue;
  }

  void _noteEmbeddedCue(String text) {
    final cue = text.trim();
    if (cue.isEmpty || !_embeddedSniffCues.add(cue)) return;
    final sample = _embeddedSniffCues.join('\n');
    final counts = sushiSubtitleScriptCounts(sample);
    if (counts.letters >= 24 || _embeddedSniffCues.length >= 6) {
      _finishEmbeddedSniff();
    }
  }

  void _finishEmbeddedSniff() {
    final pending = _embeddedSniff;
    if (pending == null || pending.isCompleted) return;
    _embeddedSniffTimer?.cancel();
    _embeddedSniffTimer = null;
    final player = _player;
    if (player is LibMPV) player.embeddedCueListener = null;
    if (player is NativePlayer) player.embeddedCueListener = null;
    pending.complete(_embeddedSniffCues.join('\n'));
  }

  void _clearEmbeddedCueListener() {
    final player = _player;
    if (player is LibMPV) player.embeddedCueListener = null;
    if (player is NativePlayer) player.embeddedCueListener = null;
  }

  /// Sample muxed cues. Persian text keeps that track and relabels it `fa`.
  ///
  /// The first window starts before the stream opens, so it often ends empty and must
  /// not send the player online. A second window runs after play. Only a Latin sample,
  /// or that second window ending with no Persian, goes online.
  Future<void> awaitEmbeddedSniffThenMaybeOnline(PlaybackModel model) async {
    final pending = _embeddedSniff;
    if (pending == null) {
      await maybeSushiStartOnlineSubtitle(model);
      return;
    }
    // Cues collected while the stream was still opening. A short sample here is not a verdict.
    var sample = _embeddedSniffCues.join('\n');
    if (!sushiSubtitleSampleLooksPersian(sample) && !sushiSubtitleSampleRejectsPersian(sample)) {
      _openEmbeddedSniffWindow(const Duration(seconds: 18));
      final again = _embeddedSniff!;
      sample = await again.future.timeout(const Duration(seconds: 20), onTimeout: () {
        _finishEmbeddedSniff();
        return _embeddedSniffCues.join('\n');
      });
    }
    if (sushiSubtitleSampleLooksPersian(sample)) {
      final index = sushiScriptSniffSubtitleIndex(model.subStreams) ??
          ref.read(playBackModel)?.mediaStreams?.defaultSubStreamIndex;
      log('sushi_sub_sniff persian index=$index chars=${sample.length}', name: 'sushi.subs');
      if (index != null && index >= 0) {
        final player = _player;
        if (player is NativePlayer) {
          await player.setEmbeddedSubtitleLanguage(index, 'fa');
        }
        final current = ref.read(playBackModel);
        final relabeled = sushiRelabelSubtitleAsPersian(current?.mediaStreams, index);
        if (current is SushiPlaybackModel && relabeled != null) {
          ref.read(playBackModel.notifier).update(
                (_) => current.copyWith(mediaStreams: () => relabeled),
              );
        }
      }
      return;
    }
    log('sushi_sub_sniff not_persian chars=${sample.length}', name: 'sushi.subs');
    _clearEmbeddedCueListener();
    await maybeSushiStartOnlineSubtitle(model);
  }

  /// Online only when the file has no muxed track for the account subtitle lang.
  /// Hardsub and Iranian items stay Off. A sniff that already proved the text is not the
  /// preferred lang calls this with the label still `en`.
  Future<void> maybeSushiStartOnlineSubtitle(PlaybackModel model, {bool forced = false}) async {
    final sourceName = model.mediaStreams?.currentVersionStream?.name;
    final hardSub = sushiMediaSourceLooksHardSub(sourceName, subStreams: model.subStreams);
    await sushiLoadAccountPlaybackPref();
    final want = sushiAccountPlaybackPref.subtitleLangOrFa;
    final preferredIndex = sushiPreferredLangStreamIndex(model.subStreams, want);
    final isIranian = SushiIranContent.isIranian(
      tags: model.item.overview.tags,
      genres: model.item.overview.genreItems,
      name: model.item.name,
      mediaStreams: model.mediaStreams,
    );
    log(
      'sushi_sub_start_choice hardSub=$hardSub preferredIndex=$preferredIndex lang=$want isIranian=$isIranian forced=$forced',
      name: 'sushi.subs',
    );
    if (!forced) {
      if (sushiAccountPlaybackPref.wantsSubtitlesOff) return;
      // Non-Persian "with subtitles" still searches online when a muxed track exists.
      final blockOnMuxed = !sushiAccountPlaybackPref.wantsAutoOnlineSubtitles && preferredIndex != null;
      if (hardSub || isIranian || blockOnMuxed) return;
    }
    final r = await sushiRunStartSubtitlePipeline(
      ref,
      player: this,
      hasPersianSoft: false,
      allowAiFallback: !hardSub,
      model: model,
    );
    log('sushi_sub_auto_result ok=${r.ok} error=${r.errorCode} label=${r.label}', name: 'sushi.subs');
    // Auto-start is silent: a miss (empty SubDL zip, no pack) is not a user-facing failure.
    // Manual Automatic / Online sheet still surfaces errors from sushiRunAutoLoad.
  }

  /// Replay a stored AI pick for this series or movie. Skips the account start gates.
  Future<void> maybeSushiStartAiSubtitle(PlaybackModel model) async {
    final r = await sushiRunTranslateToPersian(ref, forceKeyRefresh: false, player: this);
    log('sushi_sub_ai_replay ok=${r.ok} error=${r.errorCode} label=${r.label}', name: 'sushi.subs');
  }

  @override
  Future<SushiSubtitleActionResult> translateSubtitleToPersian() async {
    final r = await sushiRunTranslateToPersian(ref, player: this, remember: true);
    return SushiSubtitleActionResult(
      ok: r.ok,
      errorCode: r.errorCode,
      label: r.label,
      fileNames: r.fileNames,
      tag: r.tag,
    );
  }

  @override
  void cancelSushiSubtitle() => sushiCancelSubtitleWork();

  @override
  Future<SushiAiKeySetup> sushiAiKeySetup() async {
    final s = await sushiAiKeySetupInfo();
    return SushiAiKeySetup(deepLink: s.deepLink, telegramInstalled: s.telegramInstalled);
  }

  Future<Uint8List?> takeScreenshot() {
    final player = _player;

    if (player == null) {
      return Future.value(null);
    }

    return player.takeScreenshot();
  }
}
