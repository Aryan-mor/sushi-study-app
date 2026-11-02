import 'package:fladder/sushi/sushi_stuck_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sushiNativePlaybackLooksStuck', () {
    test('not stuck while buffering', () {
      expect(
        sushiNativePlaybackLooksStuck(
          playing: false,
          buffering: true,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isFalse,
      );
    });

    test('not stuck when playing', () {
      expect(
        sushiNativePlaybackLooksStuck(
          playing: true,
          buffering: false,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isFalse,
      );
    });

    test('not stuck when buffer advanced', () {
      expect(
        sushiNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: Duration.zero,
          buffer: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('stuck when idle at start with no buffer', () {
      expect(
        sushiNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isTrue,
      );
    });

    test('respects resume start position', () {
      const start = Duration(minutes: 10);
      expect(
        sushiNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: start,
          buffer: Duration.zero,
          startPosition: start,
        ),
        isTrue,
      );
      expect(
        sushiNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: start + const Duration(seconds: 5),
          buffer: Duration.zero,
          startPosition: start,
        ),
        isFalse,
      );
    });
  });

  group('sushiPlaybackLooksFrozenMidStream', () {
    const start = Duration(minutes: 5);
    const mid = Duration(minutes: 15);

    test('not frozen while buffering', () {
      expect(
        sushiPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: true,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('not frozen when paused', () {
      expect(
        sushiPlaybackLooksFrozenMidStream(
          playing: false,
          buffering: false,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('not frozen when position advanced', () {
      expect(
        sushiPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: mid + const Duration(seconds: 3),
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('frozen when playing but timeline stalled mid-stream', () {
      expect(
        sushiPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          duration: const Duration(hours: 2),
          startPosition: start,
        ),
        isTrue,
      );
    });

    test('buffer stall while buffering mid-stream', () {
      const start = Duration(minutes: 5);
      const mid = Duration(minutes: 25);
      expect(
        sushiPlaybackLooksBufferStalled(
          buffering: true,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          duration: const Duration(minutes: 41),
          startPosition: start,
        ),
        isTrue,
      );
    });

    test('not a buffer stall while bytes are still arriving', () {
      const mid = Duration(minutes: 25);
      expect(
        sushiPlaybackLooksBufferStalled(
          buffering: true,
          position: mid,
          previousPosition: mid,
          buffer: mid + const Duration(seconds: 4),
          previousBuffer: mid,
          duration: const Duration(minutes: 41),
        ),
        isFalse,
      );
    });

    test('not a buffer stall at the opening fill', () {
      expect(
        sushiPlaybackLooksBufferStalled(
          buffering: true,
          position: const Duration(seconds: 2),
          previousPosition: const Duration(seconds: 2),
          buffer: Duration.zero,
          previousBuffer: Duration.zero,
          duration: const Duration(minutes: 41),
        ),
        isFalse,
      );
    });

    test('not frozen near end credits', () {
      const duration = Duration(hours: 2);
      expect(
        sushiPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: duration - const Duration(seconds: 5),
          previousPosition: duration - const Duration(seconds: 5),
          buffer: duration,
          previousBuffer: duration,
          duration: duration,
          startPosition: start,
        ),
        isFalse,
      );
    });
  });

  group('SushiStuckPlaybackTracker', () {
    test('resume grace blocks immediate mid-stream false positive after pause', () {
      final tracker = SushiStuckPlaybackTracker();
      final now = DateTime(2026, 7, 6);
      const mid = Duration(hours: 2);

      tracker.onPlaybackSample(
        playing: false,
        position: mid,
        buffer: mid,
        now: now,
      );
      tracker.advanceSample(position: mid, buffer: mid);

      tracker.onPlaybackSample(
        playing: true,
        position: mid,
        buffer: mid,
        now: now.add(const Duration(seconds: 1)),
      );

      expect(tracker.inResumeGrace(now.add(const Duration(seconds: 1))), isTrue);
      expect(
        tracker.noteMidStreamFrozenSample(
          sushiPlaybackLooksFrozenMidStream(
            playing: true,
            buffering: false,
            position: mid,
            previousPosition: mid,
            buffer: mid,
            previousBuffer: mid,
            duration: const Duration(hours: 3),
          ),
        ),
        isFalse,
      );
    });

    test('buffer stall needs five frozen buffering samples', () {
      final tracker = SushiStuckPlaybackTracker();
      for (var i = 0; i < bufferStallSamplesRequired - 1; i++) {
        expect(tracker.noteBufferStallSample(true), isFalse);
      }
      expect(tracker.noteBufferStallSample(true), isTrue);
      expect(tracker.noteBufferStallSample(false), isFalse);
    });

    test('requires consecutive frozen samples after grace expires', () {
      final tracker = SushiStuckPlaybackTracker();
      const mid = Duration(hours: 2);

      expect(
        tracker.noteMidStreamFrozenSample(true),
        isFalse,
      );
      expect(
        tracker.noteMidStreamFrozenSample(true),
        isTrue,
      );
      expect(
        tracker.noteMidStreamFrozenSample(false),
        isFalse,
      );
    });
  });
}
