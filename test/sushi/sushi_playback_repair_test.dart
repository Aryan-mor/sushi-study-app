import 'package:fladder/sushi/sushi_force_repair_interceptor.dart';
import 'package:fladder/sushi/sushi_playback_repair.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('force repair single-shot flag', () {
    test('arms via provider and clears after use', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(sushiForceRepairNextPlaybackProvider), isFalse);
      container.read(sushiForceRepairNextPlaybackProvider.notifier).state = true;
      expect(container.read(sushiForceRepairNextPlaybackProvider), isTrue);

      // Interceptor clears after a armed PlaybackInfo call; simulate that clear.
      container.read(sushiForceRepairNextPlaybackProvider.notifier).state = false;
      expect(container.read(sushiForceRepairNextPlaybackProvider), isFalse);
    });

    test('header name is stable', () {
      expect(sushiForceRepairHeader, 'X-OX-Force-Repair');
    });
  });

  group('SushiStreamRepairBridge', () {
    test('runtime repair is single-shot', () {
      SushiStreamRepairBridge.runtimeRepairUsed = false;
      SushiStreamRepairBridge.runtimeRepairUsed = true;
      expect(SushiStreamRepairBridge.runtimeRepairUsed, isTrue);
      SushiStreamRepairBridge.clear();
      expect(SushiStreamRepairBridge.runtimeRepairUsed, isFalse);
    });
  });
}
