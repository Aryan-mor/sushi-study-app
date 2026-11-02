/// Decision for an incoming mpv position on a progressive Telegram stream.
///
/// mpv + `force-seekable=yes` will report `position=0` when a seek lands on
/// bytes that are not in cache yet (FLOOD_WAIT / `partial file`). Accepting
/// that zero is what the user sees as "jumped to the start".
class SushiMpvPositionDecision {
  const SushiMpvPositionDecision({
    required this.acceptIncoming,
    required this.scheduleRestore,
  });

  final bool acceptIncoming;
  final bool scheduleRestore;
}

/// Open-probe grace: mpv always seeks byte 0 after `open` to test seekability.
/// Don't fight that with restore-seeks; the loadVideo resume loop covers it.
const sushiMpvOpenProbeGrace = Duration(seconds: 2);

const _nearStart = Duration(seconds: 5);

SushiMpvPositionDecision sushiMpvPositionDecision({
  required Duration previous,
  required Duration next,
  required Duration? pendingSeek,
  required bool completed,
  required Duration sinceOpen,
}) {
  if (completed) {
    return const SushiMpvPositionDecision(acceptIncoming: true, scheduleRestore: false);
  }
  final pending = pendingSeek ?? Duration.zero;
  final userWantsStart = pendingSeek != null && pending <= _nearStart;
  if (userWantsStart) {
    return const SushiMpvPositionDecision(acceptIncoming: true, scheduleRestore: false);
  }

  final jumpToStart = next <= _nearStart && (previous >= _nearStart || pending >= _nearStart);
  if (!jumpToStart) {
    return const SushiMpvPositionDecision(acceptIncoming: true, scheduleRestore: false);
  }

  return SushiMpvPositionDecision(
    acceptIncoming: false,
    scheduleRestore: sinceOpen >= sushiMpvOpenProbeGrace,
  );
}

Duration sushiMpvRestoreTarget({
  required Duration previous,
  required Duration? pendingSeek,
}) {
  final pending = pendingSeek ?? Duration.zero;
  if (pending > _nearStart) return pending;
  return previous;
}
