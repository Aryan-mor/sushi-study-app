import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/sushi/sushi_playback_user_data_derive.dart';

void main() {
  test('unknown duration never counts as watched', () {
    expect(UserData.isPlayed(Duration.zero, Duration.zero), isNull);
    expect(UserData.isPlayed(const Duration(minutes: 15), Duration.zero), isFalse);
  });

  test('known duration still marks ≥90% watched and mid-watch in progress', () {
    const runtime = Duration(minutes: 30);
    expect(UserData.isPlayed(const Duration(minutes: 14), runtime), isFalse);
    expect(UserData.isPlayed(const Duration(minutes: 28), runtime), isTrue);
    expect(UserData.isPlayed(const Duration(seconds: 30), runtime), isNull);
  });

  test('derive mid-watch with missing player duration keeps progress via catalog', () {
    final derived = sushiDerivePlaybackUserData(
      current: const UserData(),
      position: const Duration(minutes: 15),
      runTime: sushiEffectiveRunTime(
        player: Duration.zero,
        catalog: const Duration(minutes: 30),
      ),
    );
    expect(derived.played, isFalse);
    expect(derived.progress, closeTo(50, 0.1));
    expect(derived.playbackPositionTicks, greaterThan(0));
  });

  test('derive mid-watch with no duration at all does not mark played', () {
    final derived = sushiDerivePlaybackUserData(
      current: const UserData(),
      position: const Duration(minutes: 15),
      runTime: Duration.zero,
    );
    expect(derived.played, isFalse);
    expect(derived.playbackPositionTicks, greaterThan(0));
  });

  test('player duration wins over catalog', () {
    expect(
      sushiEffectiveRunTime(
        player: const Duration(minutes: 32),
        catalog: const Duration(minutes: 30),
      ),
      const Duration(minutes: 32),
    );
  });
}
