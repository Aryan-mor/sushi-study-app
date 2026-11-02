import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Player duration wins when Exo/mpv reported one. Catalog/file runtime is the fallback when
/// native teardown reports 0 (TIME_UNSET). Zero is unknown — never treat it as finished.
Duration sushiEffectiveRunTime({
  required Duration player,
  Duration? catalog,
}) {
  if (player > Duration.zero) return player;
  if (catalog != null && catalog > Duration.zero) return catalog;
  return Duration.zero;
}

/// Matches server [DerivePlaybackPersistState] / Fladder [UserData.isPlayed].
UserData sushiDerivePlaybackUserData({
  required UserData current,
  required Duration position,
  required Duration runTime,
}) {
  final playedFlag = UserData.isPlayed(position, runTime);
  if (playedFlag == null) {
    return current.copyWith(
      playbackPositionTicks: 0,
      progress: 0,
      played: false,
      lastPlayed: DateTime.now(),
    );
  }
  if (playedFlag) {
    return current.copyWith(
      playbackPositionTicks: 0,
      progress: 0,
      played: true,
      playCount: current.playCount + (current.played ? 0 : 1),
      lastPlayed: DateTime.now(),
    );
  }
  final ticks = position.toRuntimeTicks;
  final progress = runTime.inMilliseconds > 0
      ? (position.inMilliseconds / runTime.inMilliseconds * 100).clamp(0.0, 100.0)
      : 0.0;
  return current.copyWith(
    playbackPositionTicks: ticks,
    progress: progress,
    played: false,
    lastPlayed: DateTime.now(),
  );
}

/// Resume from `/files` when the local continue store has nothing. Local always wins (R-WRITE-1).
UserData? sushiUserDataFromFiles(SushiFilesRes? files) {
  if (files == null || !files.hasProgress) return null;
  if (files.done) {
    return const UserData(played: true, progress: 0, playbackPositionTicks: 0);
  }
  final durationS = files.resumeDurationS;
  final positionMs = files.positionS * 1000;
  final durationMs = durationS * 1000;
  final progress = durationMs > 0 ? (positionMs / durationMs * 100).clamp(0.0, 100.0) : 0.0;
  return UserData(
    played: false,
    progress: progress,
    playbackPositionTicks: positionMs * 10000,
  );
}
