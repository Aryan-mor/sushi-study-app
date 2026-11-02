import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/sushi/sushi_tv_image_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clamps large backdrop request to TV cap', () {
    final (w, h) = SushiTvImageSizes.clampPair(
      maxWidth: 2000,
      maxHeight: 2000,
      cap: SushiTvImageSizes.backdrop,
    );
    expect(w, 1920);
    expect(h, 1080);
  });

  test('clamps poster request above TV primary cap', () {
    final (w, h) = SushiTvImageSizes.clampPair(
      maxWidth: 300,
      maxHeight: 300,
      cap: SushiTvImageSizes.primary,
    );
    expect(w, 280);
    expect(h, 280);
  });

  test('leaves small poster request unchanged', () {
    final (w, h) = SushiTvImageSizes.clampPair(
      maxWidth: 200,
      maxHeight: 200,
      cap: SushiTvImageSizes.primary,
    );
    expect(w, 200);
    expect(h, 200);
  });

  test('maps logo type to logo cap', () {
    final cap = SushiTvImageSizes.forImageType(ImageType.logo);
    expect(cap, SushiTvImageSizes.logo);
  });

  test('keeps default FladderImage decodeHeight at grid cap', () {
    expect(SushiTvImageSizes.clampDecodeHeight(520), 360);
  });

  test('allows explicit hero decodeHeight', () {
    expect(SushiTvImageSizes.clampDecodeHeight(720), 360);
    expect(SushiTvImageSizes.clampDecodeHeight(1080), 1080);
    expect(SushiTvImageSizes.clampDecodeHeight(1440), 1080);
  });
}
