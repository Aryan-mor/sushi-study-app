import 'package:flutter_test/flutter_test.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';

SushiAssignment _a({
  String primary = 'primaryBot',
  List<String> pool = const ['botA', 'botB', 'botC'],
}) =>
    SushiAssignment(
      apiBotUsername: primary,
      pool: pool,
      providerId: 1,
      bindingToken: 'tok',
      epoch: 1,
    );

void main() {
  setUp(() => sushiResetApiBotCursor());

  test('apiSendTargets is pool then primary, de-duped case-insensitively', () {
    final a = _a(primary: 'BotA', pool: const ['botA', ' botB ', '', 'botC']);
    expect(a.apiSendTargets, ['botA', 'botB', 'botC']);
  });

  test('apiSendTargets appends primary when pool omitted it', () {
    expect(_a(primary: 'primaryBot', pool: const ['botA']).apiSendTargets,
        ['botA', 'primaryBot']);
  });

  test('apiSendTargets falls back to primary when pool is empty', () {
    expect(_a(pool: const []).apiSendTargets, ['primaryBot']);
    expect(_a(primary: '', pool: const []).apiSendTargets, isEmpty);
  });

  test('sushiNextApiBot walks the ring in order when cursor is pinned', () {
    sushiResetApiBotCursor(0);
    final a = _a(primary: 'botA', pool: const ['botA', 'botB', 'botC']);
    expect(sushiNextApiBot(a), 'botA');
    expect(sushiNextApiBot(a), 'botB');
    expect(sushiNextApiBot(a), 'botC');
    expect(sushiNextApiBot(a), 'botA');
  });

  test('sushiNextApiBot with empty pool returns the primary', () {
    sushiResetApiBotCursor(0);
    expect(sushiNextApiBot(_a(pool: const [])), 'primaryBot');
  });

  test('sushiNextApiBot with empty assignment returns empty', () {
    sushiResetApiBotCursor(0);
    expect(sushiNextApiBot(_a(primary: '', pool: const [])), isEmpty);
  });
}
