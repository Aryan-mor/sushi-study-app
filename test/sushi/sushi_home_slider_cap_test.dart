import 'package:fladder/sushi/sushi_home_detail_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home slider PlaybackInfo warmup caps at five', () {
    expect(SushiHomeDetailPrefetch.sliderTake, 5);
  });
}
