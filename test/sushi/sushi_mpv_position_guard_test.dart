import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/playback/sushi_mpv_position_guard.dart';

void main() {
  const pendingResume = Duration(minutes: 68);

  test('resume stuck at 0 during open probe does not restore-seek yet', () {
    final d = sushiMpvPositionDecision(
      previous: Duration.zero,
      next: Duration.zero,
      pendingSeek: pendingResume,
      completed: false,
      sinceOpen: const Duration(milliseconds: 400),
    );
    expect(d.acceptIncoming, isFalse);
    expect(d.scheduleRestore, isFalse);
  });

  test('resume still at 0 after probe grace restores to pending', () {
    final d = sushiMpvPositionDecision(
      previous: Duration.zero,
      next: Duration.zero,
      pendingSeek: pendingResume,
      completed: false,
      sinceOpen: const Duration(seconds: 3),
    );
    expect(d.acceptIncoming, isFalse);
    expect(d.scheduleRestore, isTrue);
    expect(
      sushiMpvRestoreTarget(previous: Duration.zero, pendingSeek: pendingResume),
      pendingResume,
    );
  });

  test('user seek to start is accepted', () {
    final d = sushiMpvPositionDecision(
      previous: pendingResume,
      next: Duration.zero,
      pendingSeek: Duration.zero,
      completed: false,
      sinceOpen: const Duration(minutes: 10),
    );
    expect(d.acceptIncoming, isTrue);
    expect(d.scheduleRestore, isFalse);
  });

  test('next episode at zero is not previous-episode restore', () {
    final d = sushiMpvPositionDecision(
      previous: const Duration(minutes: 28),
      next: Duration.zero,
      pendingSeek: Duration.zero,
      completed: false,
      sinceOpen: const Duration(seconds: 3),
    );
    expect(d.acceptIncoming, isTrue);
    expect(d.scheduleRestore, isFalse);
  });

  test('normal playback advance is accepted', () {
    final d = sushiMpvPositionDecision(
      previous: const Duration(minutes: 10),
      next: const Duration(minutes: 10, seconds: 1),
      pendingSeek: null,
      completed: false,
      sinceOpen: const Duration(minutes: 10),
    );
    expect(d.acceptIncoming, isTrue);
    expect(d.scheduleRestore, isFalse);
  });

  test('forward seek that lands at 0 restores to pending', () {
    final d = sushiMpvPositionDecision(
      previous: const Duration(seconds: 20),
      next: Duration.zero,
      pendingSeek: const Duration(minutes: 80),
      completed: false,
      sinceOpen: const Duration(minutes: 5),
    );
    expect(d.acceptIncoming, isFalse);
    expect(d.scheduleRestore, isTrue);
    expect(
      sushiMpvRestoreTarget(
        previous: const Duration(seconds: 20),
        pendingSeek: const Duration(minutes: 80),
      ),
      const Duration(minutes: 80),
    );
  });

  test('demuxer reset without pending restore to previous', () {
    final d = sushiMpvPositionDecision(
      previous: const Duration(minutes: 40),
      next: Duration.zero,
      pendingSeek: null,
      completed: false,
      sinceOpen: const Duration(minutes: 20),
    );
    expect(d.acceptIncoming, isFalse);
    expect(d.scheduleRestore, isTrue);
    expect(
      sushiMpvRestoreTarget(previous: const Duration(minutes: 40), pendingSeek: null),
      const Duration(minutes: 40),
    );
  });

  test('completed at zero is accepted', () {
    final d = sushiMpvPositionDecision(
      previous: const Duration(hours: 1),
      next: Duration.zero,
      pendingSeek: null,
      completed: true,
      sinceOpen: const Duration(hours: 1),
    );
    expect(d.acceptIncoming, isTrue);
  });
}
