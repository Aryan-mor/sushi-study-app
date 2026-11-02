import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/sushi/sushi_tv_image_sizes.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/image_provider.dart';

/// Caps Jellyfin image fill dimensions on leanback TV to reduce decode RAM.
class SushiImageNotifier extends ImageNotifier {
  SushiImageNotifier({required super.ref});

  bool get _leanBack => ref.read(argumentsStateProvider).leanBackMode;

  @override
  String getItemsImageUrl(
    String? itemId, {
    ImageType type = ImageType.primary,
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = SushiTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: SushiTvImageSizes.forImageType(type),
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getItemsImageUrl(
      itemId,
      type: type,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }

  @override
  String getBackdropImage(
    String itemId,
    int index,
    String hash, {
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = SushiTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: SushiTvImageSizes.backdrop,
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getBackdropImage(
      itemId,
      index,
      hash,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }

  @override
  String getChapterUrl(
    String itemId,
    int index, {
    ImageType type = ImageType.primary,
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = SushiTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: SushiTvImageSizes.primary,
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getChapterUrl(
      itemId,
      index,
      type: type,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }
}
