import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/sushi/sushi_provider_read.dart';
import 'package:fladder/sushi/sushi_playback_repair.dart';
import 'package:fladder/sushi/sushi_playback_telemetry.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

/// True when the Android native (ExoPlayer) backend is selected.
bool sushiUsesNativePlayer(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

bool sushiUsesNativePlayerRead(Ref ref) {
  if (kIsWeb || !Platform.isAndroid) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

/// True when Android uses in-app MPV (typical phone/tablet layout).
bool sushiUsesMpvPlayerOnAndroid(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.libMPV;
}

bool sushiUsesMpvPlayerOnAndroidRead(Ref ref) {
  if (kIsWeb || !Platform.isAndroid) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.libMPV;
}

bool _shouldScheduleStuckWatch(SushiRead read) {
  if (kIsWeb) return false;
  // Desktop libmpv uses the same gotd chunk fetch as Android MPV. A hung
  // upload.getFile leaves the frame frozen in buffering; closing the player
  // was the only recovery because this watch used to be Android-only.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return true;
  if (!Platform.isAndroid) return false;
  final player = read(videoPlayerSettingsProvider).wantedPlayer;
  return player == PlayerOptions.nativePlayer || player == PlayerOptions.libMPV;
}

/// Intentionally disabled: launching the activity before [loadPlaybackItem] causes ExoPlayer
/// to bind and sit idle while Dart finishes stop()/network work. The user sees a black screen
/// and presses Back before the URL arrives. The standard flow (openPlayer after loadPlaybackItem)
/// is correct: pendingOpenUrl is set by open(), then init() picks it up when ExoPlayer binds.
Future<bool> sushiOpenNativePlayerEarly(SushiRead read, BuildContext context) async {
  return false;
}

const stuckPlaybackCheckDelay = Duration(seconds: 12);
const midStreamResumeGrace = Duration(seconds: 45);
/// CDN resume seek (large startPosition) can take 30–60s before ExoPlayer reports progress.
const startResumeSeekGrace = Duration(seconds: 90);
const _maxStuckRetries = 3;

/// Consecutive mid-stream frozen samples required before auto-repair (avoids pause/resume false positives).
@visibleForTesting
const midStreamFrozenSamplesRequired = 2;

/// Consecutive buffering samples with a frozen playhead and buffer head before auto-repair.
/// Five ticks of [stuckPlaybackCheckDelay] (60s) sit past the Go chunk retries
/// (3 × 20s) so a slow-but-alive download is not reloaded out from under itself.
@visibleForTesting
const bufferStallSamplesRequired = 5;

/// Tracks pause/resume transitions so mid-stream freeze is not inferred right after play resumes.
@visibleForTesting
class SushiStuckPlaybackTracker {
  SushiStuckPlaybackTracker({Duration startPosition = Duration.zero})
      : previousPosition = startPosition;

  Duration previousPosition;
  Duration previousBuffer = Duration.zero;
  bool? lastPlaying;
  DateTime? resumeGraceUntil;
  int consecutiveMidStreamFrozen = 0;
  int consecutiveBufferStalled = 0;

  bool inResumeGrace([DateTime? now]) {
    final until = resumeGraceUntil;
    if (until == null) return false;
    return (now ?? DateTime.now()).isBefore(until);
  }

  void onPlaybackSample({
    required bool playing,
    required Duration position,
    required Duration buffer,
    required DateTime now,
  }) {
    if (lastPlaying == false) {
      resumeGraceUntil = now.add(midStreamResumeGrace);
      consecutiveMidStreamFrozen = 0;
      consecutiveBufferStalled = 0;
      previousPosition = position;
      previousBuffer = buffer;
    } else if (lastPlaying == !playing) {
      resumeGraceUntil = null;
      consecutiveMidStreamFrozen = 0;
      consecutiveBufferStalled = 0;
    }
    lastPlaying = playing;
  }

  bool noteMidStreamFrozenSample(bool frozen) {
    if (!frozen) {
      consecutiveMidStreamFrozen = 0;
      return false;
    }
    consecutiveMidStreamFrozen++;
    return consecutiveMidStreamFrozen >= midStreamFrozenSamplesRequired;
  }

  bool noteBufferStallSample(bool stalled) {
    if (!stalled) {
      consecutiveBufferStalled = 0;
      return false;
    }
    consecutiveBufferStalled++;
    return consecutiveBufferStalled >= bufferStallSamplesRequired;
  }

  void advanceSample({required Duration position, required Duration buffer}) {
    previousPosition = position;
    previousBuffer = buffer;
  }

  void resetIncident() {
    consecutiveMidStreamFrozen = 0;
    consecutiveBufferStalled = 0;
    resumeGraceUntil = null;
  }
}

/// True when the player appears idle right after open (not merely buffering a cold stream).
@visibleForTesting
bool sushiNativePlaybackLooksStuck({
  required bool playing,
  required bool buffering,
  required Duration position,
  required Duration buffer,
  Duration startPosition = Duration.zero,
}) {
  if (buffering || playing) return false;
  if (buffer > const Duration(seconds: 2)) return false;
  return position <= startPosition + const Duration(seconds: 2);
}

/// True when playback claims to be active but timeline/buffer head stopped advancing.
@visibleForTesting
bool sushiPlaybackLooksFrozenMidStream({
  required bool playing,
  required bool buffering,
  required Duration position,
  required Duration previousPosition,
  required Duration buffer,
  required Duration previousBuffer,
  Duration? duration,
  Duration startPosition = Duration.zero,
}) {
  if (buffering || !playing) return false;

  final positionMoved = (position - previousPosition).inSeconds.abs() >= 1;
  final bufferMoved = (buffer - previousBuffer).inSeconds.abs() >= 1;
  if (positionMoved || bufferMoved) return false;

  if (position <= startPosition + const Duration(seconds: 5)) return false;

  if (duration != null && duration > Duration.zero) {
    if (position >= duration - const Duration(seconds: 10)) return false;
  }

  return true;
}

/// True when the player is waiting on bytes and neither the playhead nor the
/// buffered range has moved. Normal readahead moves [buffer] even while
/// [buffering] is set; a hung chunk fetch moves neither, and the play control
/// stays hidden until something reloads the session.
@visibleForTesting
bool sushiPlaybackLooksBufferStalled({
  required bool buffering,
  required Duration position,
  required Duration previousPosition,
  required Duration buffer,
  required Duration previousBuffer,
  Duration? duration,
  Duration startPosition = Duration.zero,
}) {
  if (!buffering) return false;

  final positionMoved = (position - previousPosition).inSeconds.abs() >= 1;
  final bufferMoved = (buffer - previousBuffer).inSeconds.abs() >= 1;
  if (positionMoved || bufferMoved) return false;

  // Opening fill and the first seconds after a seek still look like this.
  if (position <= startPosition + const Duration(seconds: 5)) return false;

  if (duration != null && duration > Duration.zero) {
    if (position >= duration - const Duration(seconds: 10)) return false;
  }

  return true;
}

/// Cancelable handle for [sushiScheduleStuckPlaybackWatch].
///
/// A plain [Timer] cannot represent this watch: each check reschedules itself onto a *new*
/// one-shot Timer, so a caller holding only the Timer returned by the initial call would be
/// calling cancel() on an already-fired Timer as soon as one tick had elapsed — a no-op that
/// left the real, currently-running Timer (held only by the closure) ticking forever. That bug
/// let stuck-playback polling outlive the player screen it was watching, accumulating orphaned
/// 12s-interval timers across every exit that happened after the first tick.
class StuckPlaybackWatch {
  Timer? _timer;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }
}

/// Periodically detects start-stuck, mid-stream freeze, and a buffering stall.
/// Android native ExoPlayer is observed only (a full reload spikes RAM and gets the TV killed).
/// Android MPV and desktop libmpv reload the item, which is the same recovery as closing the player.
StuckPlaybackWatch? sushiScheduleStuckPlaybackWatch({
  required SushiRead read,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
  Duration startPosition = Duration.zero,
}) {
  if (!_shouldScheduleStuckWatch(read)) return null;

  final watch = StuckPlaybackWatch();
  var retriesUsed = 0;
  var telemetrySentForIncident = false;
  var exhaustedReported = false;
  final tracker = SushiStuckPlaybackTracker(startPosition: startPosition);
  final startResumeGraceUntil = startPosition > const Duration(seconds: 30)
      ? DateTime.now().add(startResumeSeekGrace)
      : null;

  // Declared as late variables (rather than function-declaration statements) so the two can
  // reference each other: `reschedule` calls `runStuckCheck` before it exists yet, which Dart
  // only allows for a variable, not a local function declaration.
  late final void Function() reschedule;
  late final Future<void> Function() runStuckCheck;

  reschedule = () {
    if (watch._cancelled) return;
    watch._timer = Timer(stuckPlaybackCheckDelay, () => unawaited(runStuckCheck()));
  };

  runStuckCheck = () async {
    if (watch._cancelled) return;

    final sessionRef = SushiStreamRepairBridge.ref;
    if (sessionRef == null) {
      return;
    }

    final playback = sessionRef.read(mediaPlaybackProvider);
    final model = sessionRef.read(playBackModel);
    if (model == null || model.item.id != itemId) {
      return;
    }

    final now = DateTime.now();
    tracker.onPlaybackSample(
      playing: playback.playing,
      position: playback.position,
      buffer: playback.buffer,
      now: now,
    );

    final startStuck = sushiNativePlaybackLooksStuck(
      playing: playback.playing,
      buffering: playback.buffering,
      position: playback.position,
      buffer: playback.buffer,
      startPosition: startPosition,
    );

    final inStartResumeGrace =
        startResumeGraceUntil != null && now.isBefore(startResumeGraceUntil);
    final startStuckEffective = startStuck && !inStartResumeGrace;

    final frozenSample = !tracker.inResumeGrace(now) &&
        sushiPlaybackLooksFrozenMidStream(
          playing: playback.playing,
          buffering: playback.buffering,
          position: playback.position,
          previousPosition: tracker.previousPosition,
          buffer: playback.buffer,
          previousBuffer: tracker.previousBuffer,
          duration: playback.duration.inSeconds > 0 ? playback.duration : catalogDuration,
          startPosition: startPosition,
        );
    final midStreamFrozen = tracker.noteMidStreamFrozenSample(frozenSample);

    final bufferStalledSample = !tracker.inResumeGrace(now) &&
        !inStartResumeGrace &&
        sushiPlaybackLooksBufferStalled(
          buffering: playback.buffering,
          position: playback.position,
          previousPosition: tracker.previousPosition,
          buffer: playback.buffer,
          previousBuffer: tracker.previousBuffer,
          duration: playback.duration.inSeconds > 0 ? playback.duration : catalogDuration,
          startPosition: startPosition,
        );
    final bufferStalled = tracker.noteBufferStallSample(bufferStalledSample);

    tracker.advanceSample(position: playback.position, buffer: playback.buffer);

    final stuck = startStuckEffective || midStreamFrozen || bufferStalled;
    if (!stuck) {
      retriesUsed = 0;
      telemetrySentForIncident = false;
      exhaustedReported = false;
      reschedule();
      return;
    }

    // Native ExoPlayer runs in VideoPlayerActivity while MainActivity keeps the Flutter
    // engine alive. Full reload from Dart mid-playback spikes RAM and causes TV kills.
    if (sushiUsesNativePlayerRead(sessionRef)) {
      if (!telemetrySentForIncident) {
        telemetrySentForIncident = true;
        unawaited(SushiPlaybackTelemetry.reportStuckPlayback(
          itemId: itemId,
          streamUrl: streamUrl,
          position: playback.position,
          catalogDuration: catalogDuration,
          nativePlayer: true,
          stuckKind: bufferStalled
              ? 'buffer_stall'
              : midStreamFrozen
                  ? 'mid_stream'
                  : 'start',
          transient: false,
        ));
      }
      reschedule();
      return;
    }

    if (retriesUsed >= _maxStuckRetries) {
      if (!exhaustedReported) {
        exhaustedReported = true;
        unawaited(SushiPlaybackTelemetry.reportFailure(
          stage: 'player_stuck',
          reason: bufferStalled
              ? 'buffer_stall_exhausted_retries'
              : midStreamFrozen
                  ? 'mid_stream_exhausted_retries'
                  : 'zero_progress_exhausted_retries',
          itemId: itemId,
          streamUrl: streamUrl,
          extra: {'retries': retriesUsed},
        ));
      }
      reschedule();
      return;
    }

    if (!telemetrySentForIncident) {
      telemetrySentForIncident = true;
      unawaited(SushiPlaybackTelemetry.reportStuckPlayback(
        itemId: itemId,
        streamUrl: streamUrl,
        position: playback.position,
        catalogDuration: catalogDuration,
        nativePlayer: sushiUsesNativePlayerRead(sessionRef),
        stuckKind: bufferStalled
            ? 'buffer_stall'
            : midStreamFrozen
                ? 'mid_stream'
                : 'start',
        transient: true,
      ));
    }

    retriesUsed++;
    final resumeAt = playback.position;
    final refreshed = await sushiRefreshPlaybackWithForceRepair(
      sessionRef.read,
      model,
      startPosition: resumeAt,
    );
    final retryModel = refreshed ?? model;
    await sessionRef.read(videoPlayerProvider.notifier).loadPlaybackItem(retryModel, resumeAt);

    tracker.resetIncident();
    reschedule();
  };

  reschedule();
  return watch;
}

/// Back-compat alias.
StuckPlaybackWatch? sushiScheduleNativeStuckPlaybackWatch({
  required SushiRead read,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
  Duration startPosition = Duration.zero,
}) =>
    sushiScheduleStuckPlaybackWatch(
      read: read,
      itemId: itemId,
      streamUrl: streamUrl,
      catalogDuration: catalogDuration,
      startPosition: startPosition,
    );
