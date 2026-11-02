import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_slider_image.dart';

void main() {
  test('slider backdrop is TMDB w1280, not the compact w500 poster', () {
    final base = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 80,
        poster: 'fc_poster',
      ),
    ) as MovieModel;
    final item = base.copyWith(
      images: ImagesData(
        primary: base.images?.primary,
        backDrop: [
          ImageData(
            path: 'https://image.tmdb.org/t/p/w780/fc_bd.jpg',
            key: 'bd',
          ),
        ],
      ),
    );
    expect(sushiSliderImage(item)?.path, 'https://image.tmdb.org/t/p/w1280/fc_bd.jpg');
  });

  test('slider poster fallback uses w780 while backdrop is missing', () {
    final item = sushiRowToItemBaseModel(
      const SushiRow(
        tmdbId: 550,
        kind: SushiKind.movie,
        title: 'Fight Club',
        year: 1999,
        rating: 80,
        poster: 'fc_poster',
      ),
    );
    expect(item.images?.primary?.path, contains('/w500/fc_poster.jpg'));
    expect(sushiSliderImage(item)?.path, contains('/w780/fc_poster.jpg'));
  });
}
