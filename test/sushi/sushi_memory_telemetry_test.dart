import 'package:fladder/sushi/sushi_memory_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TV threshold lower than phone', () {
    expect(
      SushiMemoryTelemetry.highMemoryThresholdMb(leanBack: true),
      lessThan(SushiMemoryTelemetry.highMemoryThresholdMb(leanBack: false)),
    );
  });

  test('warns when RSS exceeds absolute threshold', () {
    final snapshot = SushiMemorySnapshot(
      rssBytes: 600 * 1024 * 1024,
      imageCacheBytes: 0,
      imageCacheCount: 0,
      imageCacheMaxBytes: 100 * 1024 * 1024,
    );

    expect(
      SushiMemoryTelemetry.shouldWarn(
        snapshot: snapshot,
        previous: null,
        leanBack: false,
        route: 'HomeRoute',
        lastWarningScreen: null,
        lastWarningAt: null,
        now: DateTime.utc(2026, 1, 1),
      ),
      isTrue,
    );
  });

  test('warns when RSS jumps on navigation', () {
    final previous = SushiMemorySnapshot(
      rssBytes: 200 * 1024 * 1024,
      imageCacheBytes: 0,
      imageCacheCount: 0,
      imageCacheMaxBytes: 100 * 1024 * 1024,
    );
    final snapshot = SushiMemorySnapshot(
      rssBytes: 280 * 1024 * 1024,
      imageCacheBytes: 0,
      imageCacheCount: 0,
      imageCacheMaxBytes: 100 * 1024 * 1024,
    );

    expect(
      SushiMemoryTelemetry.shouldWarn(
        snapshot: snapshot,
        previous: previous,
        leanBack: false,
        route: 'SeriesDetailRoute',
        lastWarningScreen: null,
        lastWarningAt: null,
        now: DateTime.utc(2026, 1, 1),
      ),
      isTrue,
    );
  });

  test('cooldown suppresses duplicate warnings for same screen', () {
    final snapshot = SushiMemorySnapshot(
      rssBytes: 600 * 1024 * 1024,
      imageCacheBytes: 0,
      imageCacheCount: 0,
      imageCacheMaxBytes: 100 * 1024 * 1024,
    );
    final now = DateTime.utc(2026, 1, 1, 12, 0, 30);

    expect(
      SushiMemoryTelemetry.shouldWarn(
        snapshot: snapshot,
        previous: null,
        leanBack: false,
        route: 'HomeRoute',
        lastWarningScreen: 'HomeRoute',
        lastWarningAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
        now: now,
      ),
      isFalse,
    );
  });
}
