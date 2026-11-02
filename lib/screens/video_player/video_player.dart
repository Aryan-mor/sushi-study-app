import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/components/video_player_guide_wrapper.dart';
import 'package:fladder/screens/video_player/components/video_player_next_wrapper.dart';
import 'package:fladder/screens/video_player/video_player_controls.dart';
import 'package:fladder/sushi/sushi_env.dart';
import 'package:fladder/sushi/sushi_playback_repair.dart';
import 'package:fladder/sushi/sushi_stuck_playback.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/themes_data.dart';
import 'package:fladder/widgets/shared/back_intent_dpad.dart';

class VideoPlayer extends ConsumerStatefulWidget {
  const VideoPlayer({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends ConsumerState<VideoPlayer> with WidgetsBindingObserver {
  double lastScale = 0.0;

  bool errorPlaying = false;
  bool playing = false;
  bool _resumeRecoveryInFlight = false;

  late PlaybackModel? currentPlaybackModel = ref.read(playBackModel);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    //Don't pause on desktop focus loss
    if (!(AdaptiveLayout.of(context).isDesktop || kIsWeb)) {
      switch (state) {
        case AppLifecycleState.resumed:
          if (playing) {
            ref.read(videoPlayerProvider).play();
            if (SushiEnv.isEnabled && sushiUsesNativePlayer(ref)) {
              unawaited(_recoverNativePlayerAfterResume());
            }
          }
          break;
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          if (playing) ref.read(videoPlayerProvider).pause();
          break;
        default:
          break;
      }
    }
  }

  /// TV standby can kill the native VideoPlayerActivity while the Flutter engine (and this
  /// widget) stay alive: [NativePlayer.play] then keeps sending Pigeon calls into a dead
  /// Activity, so the screen comes back black and the play button does nothing. There is no
  /// signal telling Dart the Activity died, so this samples position/buffer right after resume
  /// and, if nothing moved a few seconds later, does the one full reload (relaunch + reopen +
  /// reseek) that already exists for mid-stream repair. Bounded to a single attempt per resume
  /// so it can't turn into the repeated-reload/RAM-spike pattern that repair is deliberately
  /// disabled for during ordinary playback (see sushi_stuck_playback.dart).
  Future<void> _recoverNativePlayerAfterResume() async {
    if (_resumeRecoveryInFlight) return;
    final model = ref.read(playBackModel);
    if (model == null) return;
    _resumeRecoveryInFlight = true;
    try {
      final before = ref.read(mediaPlaybackProvider);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      if (ref.read(playBackModel)?.item.id != model.item.id) return;

      final after = ref.read(mediaPlaybackProvider);
      final stuck = !after.buffering && (after.position - before.position).inMilliseconds.abs() < 500;
      if (!stuck) return;

      final resumeAt = after.position;
      final refreshed = await sushiRefreshPlaybackWithForceRepair(ref.read, model, startPosition: resumeAt);
      await ref.read(videoPlayerProvider.notifier).loadPlaybackItem(refreshed ?? model, resumeAt);
    } finally {
      _resumeRecoveryInFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));
      final orientations = ref.read(videoPlayerSettingsProvider.select((value) => value.allowedOrientations));
      SystemChrome.setPreferredOrientations(
          orientations?.isNotEmpty == true ? orientations!.toList() : DeviceOrientation.values);
      return ref.read(videoPlayerSettingsProvider.notifier).setSavedBrightness();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fillScreen = ref.watch(videoPlayerSettingsProvider.select((value) => value.fillScreen));
    final videoFit = ref.watch(videoPlayerSettingsProvider.select((value) => value.videoFit));
    final padding = MediaQuery.of(context).padding;

    final playerController = ref.watch(videoPlayerProvider.select((value) => value));

    // didChangeAppLifecycleState reads this outside the widget tree's build/rebuild cycle, so it
    // needs a plain field kept in sync here rather than a ref.watch of its own.
    ref.listen(
      mediaPlaybackProvider.select((value) => value.playing),
      (previous, next) => playing = next,
    );

    //Watch playbackModel type changes to switch between normal players
    ref.listen(
      playBackModel,
      (previous, next) {
        if (next == null) return;
        if (previous.runtimeType != next.runtimeType) {
          setState(() {
            currentPlaybackModel = next;
            errorPlaying = false;
          });
        }
      },
    );

    ref.listen(
      videoPlayerSettingsProvider.select((value) => value.allowedOrientations),
      (previous, next) {
        if (previous != next) {
          SystemChrome.setPreferredOrientations(next?.isNotEmpty == true ? next!.toList() : DeviceOrientation.values);
        }
      },
    );

    final player = Padding(
      padding: fillScreen ? EdgeInsets.zero : EdgeInsets.only(left: padding.left, right: padding.right),
      child: playerController.videoWidget(
        const Key("VideoPlayer"),
        fillScreen ? (MediaQuery.of(context).orientation == Orientation.portrait ? videoFit : BoxFit.cover) : videoFit,
      ),
    );

    return BackIntentDpad(
      child: Material(
        color: Colors.black,
        child: Theme(
          data: ThemesData.of(context).dark,
          child: Container(
            color: Colors.black,
            child: GestureDetector(
              onScaleUpdate: (details) {
                lastScale = details.scale;
              },
              onScaleEnd: (details) {
                if (lastScale < 1.0) {
                  ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(false, context: context);
                } else if (lastScale > 1.0) {
                  ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(true, context: context);
                }
                lastScale = 0.0;
              },
              child: switch (currentPlaybackModel) {
                TvPlaybackModel _ => VideoPlayerGuideWrapper(
                    key: const Key("VideoPlayerGuideWrapper"),
                    child: player,
                  ),
                _ => VideoPlayerNextWrapper(
                    video: player,
                    controls: const DesktopControls(),
                    overlays: [
                      if (errorPlaying) const _VideoErrorWidget(),
                    ],
                  ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoErrorWidget extends StatelessWidget {
  const _VideoErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            "Error playing file",
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}
