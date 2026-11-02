import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_play_warmup.dart';

void main() {
  test('warmup caches delivered and skips a second /play', () async {
    var plays = 0;
    var acks = 0;
    final warmup = SushiPlayWarmup(
      play: ({required fileId, force = false}) async {
        plays++;
        return SushiPlayRes(
          delivered: SushiDelivered(botId: 3, messageId: 99, locator: sushiLocatorForFile(fileId)),
        );
      },
      arm: (_) async {},
      ack: ({required fileId, required messageId}) async {
        acks++;
      },
      poll: (_) async => null,
    );

    warmup.schedule(42);
    final first = await warmup.wait(42);
    expect(first?.messageId, 99);
    expect(plays, 1);
    expect(acks, 1);

    warmup.schedule(42);
    await warmup.wait(42);
    expect(plays, 1);
  });

  test('pending /play waits on poll then acks', () async {
    var plays = 0;
    final warmup = SushiPlayWarmup(
      play: ({required fileId, force = false}) async {
        plays++;
        return SushiPlayRes(pending: SushiPending(locator: sushiLocatorForFile(fileId)));
      },
      arm: (_) async {},
      ack: ({required fileId, required messageId}) async {},
      poll: (_) async => SushiTdlibDeliveryRef(providerBotId: 8, messageId: 77),
    );

    warmup.schedule(5);
    final got = await warmup.wait(5);
    expect(plays, 1);
    expect(got?.botId, 8);
    expect(got?.messageId, 77);
  });

  test('invalidate drops cache so the next schedule plays again', () async {
    var plays = 0;
    final warmup = SushiPlayWarmup(
      play: ({required fileId, force = false}) async {
        plays++;
        return SushiPlayRes(
          delivered: SushiDelivered(botId: 1, messageId: 1, locator: sushiLocatorForFile(fileId)),
        );
      },
      arm: (_) async {},
      ack: ({required fileId, required messageId}) async {},
      poll: (_) async => null,
    );

    warmup.schedule(9);
    await warmup.wait(9);
    warmup.invalidate(9);
    warmup.schedule(9);
    await warmup.wait(9);
    expect(plays, 2);
  });

  test('schedule ignores non-positive file ids', () {
    final warmup = SushiPlayWarmup(
      play: ({required fileId, force = false}) async => fail('must not play'),
      arm: (_) async {},
      ack: ({required fileId, required messageId}) async {},
      poll: (_) async => null,
    );
    warmup.schedule(0);
    warmup.schedule(null);
  });

  test('pause defers /play until resume', () async {
    var plays = 0;
    final warmup = SushiPlayWarmup(
      play: ({required fileId, force = false}) async {
        plays++;
        return SushiPlayRes(
          delivered: SushiDelivered(botId: 1, messageId: 2, locator: sushiLocatorForFile(fileId)),
        );
      },
      arm: (_) async {},
      ack: ({required fileId, required messageId}) async {},
      poll: (_) async => null,
    );

    warmup.pause();
    warmup.schedule(11);
    await Future<void>.delayed(Duration.zero);
    expect(plays, 0);

    warmup.resume();
    final got = await warmup.wait(11);
    expect(plays, 1);
    expect(got?.messageId, 2);
  });
}
