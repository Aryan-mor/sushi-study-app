import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/sushi/sushi_hero_image.dart';
import 'package:fladder/sushi/sushi_image_log.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

/// Home slider is landscape; prefer backdrop over the 600px primary poster.
/// Backdrop goes out at TMDB w1280 (hero). Poster fallback stays w780, not a stretched w500.
ImageData? sushiSliderImage(ItemBaseModel item) {
  final backdrop = item.images?.backDrop?.firstOrNull ?? item.getPosters?.backDrop?.firstOrNull;
  final hero = sushiHeroImage(backdrop ?? item.bannerImage);
  final image = sushiTmdbImageAtSize(
    hero,
    backdrop != null ? sushiTmdbSliderBackdropSize : sushiTmdbDetailSize,
  );
  SushiImageLog.event('slider', fields: {
    'item': item.id,
    'path': image?.path ?? '(none)',
  });
  return image;
}
