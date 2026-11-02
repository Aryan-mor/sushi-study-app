import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/sushi/sushi_telegram_stream_cb.dart';

void main() {
  test('stream_cb stays Windows-only so Android never dlopens a second Go runtime', () {
    expect(sushiTelegramStreamCbSupported(TargetPlatform.windows), isTrue);
    expect(sushiTelegramStreamCbSupported(TargetPlatform.android), isFalse);
    expect(sushiTelegramStreamCbSupported(TargetPlatform.iOS), isFalse);
    expect(sushiTelegramStreamCbSupported(TargetPlatform.linux), isFalse);
    expect(sushiTelegramStreamCbSupported(TargetPlatform.macOS), isFalse);
  });
}
