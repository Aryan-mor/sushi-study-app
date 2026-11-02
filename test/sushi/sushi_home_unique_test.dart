import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

SushiRow _row(int tmdbId, {SushiKind kind = SushiKind.movie, String title = ''}) => SushiRow(
      tmdbId: tmdbId,
      kind: kind,
      title: title.isEmpty ? '$tmdbId' : title,
      year: 2020,
      rating: 1,
      poster: '',
    );

ItemBaseModel _item(int tmdbId, {SushiKind kind = SushiKind.movie, String title = ''}) =>
    sushiRowToItemBaseModel(_row(tmdbId, kind: kind, title: title));

void main() {
  test('combined carousel drops slider copies of resume titles', () {
    final resume = [_item(1, title: 'A'), _item(2, title: 'B')];
    final slider = [_item(1, title: 'A'), _item(2, title: 'B'), _item(3, title: 'C')];
    final items = sushiAssembleHomeCarousel(
      settings: HomeCarouselSettings.combined,
      nextUp: slider,
      resume: resume,
    );
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['1:1', '2:1', '3:1']);
  });

  test('carousel pins trending movie then trending series first', () {
    final items = sushiAssembleHomeCarousel(
      settings: HomeCarouselSettings.combined,
      nextUp: [_item(10), _item(20, kind: SushiKind.series)],
      resume: [_item(1), _item(2, kind: SushiKind.series)],
      trendingMovies: [_item(99, title: 'Trend movie'), _item(98)],
      trendingSeries: [_item(88, kind: SushiKind.series, title: 'Trend series')],
    );
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['99:1', '88:2', '1:1', '2:2', '10:1', '20:2']);
  });

  test('carousel falls back to slider movie then series when trending empty', () {
    final items = sushiAssembleHomeCarousel(
      settings: HomeCarouselSettings.nextUp,
      nextUp: [_item(10), _item(11), _item(20, kind: SushiKind.series)],
      resume: [_item(1)],
    );
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['10:1', '20:2', '11:1']);
  });

  test('resume-only carousel keeps resume order', () {
    final items = sushiAssembleHomeCarousel(
      settings: HomeCarouselSettings.cont,
      nextUp: [_item(10)],
      resume: [_item(1), _item(2, kind: SushiKind.series)],
      trendingMovies: [_item(99)],
      trendingSeries: [_item(88, kind: SushiKind.series)],
    );
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['1:1', '2:2']);
  });

  test('continue rail keeps titles already on the banner', () {
    final seen = <String>{};
    sushiTakeUnseenHomeItems([_item(1), _item(2)], seen);
    final cw = sushiAssembleContinueRail([_item(1), _item(3)], seen);
    expect(cw.map(sushiHomeItemKey).toList(), ['1:1', '3:1']);
    final leftover = sushiTakeUnseenHomeItems([_item(1), _item(3), _item(4)], seen);
    expect(leftover.map(sushiHomeItemKey).toList(), ['4:1']);
  });

  test('same TMDB movie and series stay both', () {
    final items = sushiUniqueHomeItems([
      _item(550, kind: SushiKind.movie, title: 'Fight Club'),
      _item(550, kind: SushiKind.series, title: 'Fight Club TV'),
    ]);
    expect(items.map((e) => sushiHomeItemKey(e)).toList(), ['550:1', '550:2']);
  });

  test('only the first banner slide is hidden from later rails', () {
    final banner = [_item(1), _item(2), _item(3)];
    expect(sushiHomeBannerExcluded(const []), isEmpty);
    expect(sushiHomeBannerExcluded(banner).map(sushiHomeItemKey).toList(), ['1:1']);
    final seen = <String>{};
    sushiTakeUnseenHomeItems(sushiHomeBannerExcluded(banner), seen);
    final leftover = sushiTakeUnseenHomeItems([_item(1), _item(2), _item(3), _item(4)], seen);
    expect(leftover.map(sushiHomeItemKey).toList(), ['2:1', '3:1', '4:1']);
  });

  test('later rail drops titles already on the banner', () {
    final banner = [_item(1), _item(2), _item(3)];
    final seen = <String>{};
    sushiTakeUnseenHomeItems(banner, seen);
    final leftover = sushiTakeUnseenHomeItems(
      [_item(1), _item(2), _item(4)],
      seen,
    );
    expect(leftover.map(sushiHomeItemKey).toList(), ['4:1']);
  });

  test('banner cap does not hide overflow slider titles on the next rail', () {
    final slider = [_item(1), _item(2), _item(3), _item(4), _item(5), _item(6)];
    final banner = slider.take(5).toList();
    final seen = <String>{};
    sushiTakeUnseenHomeItems(banner, seen);
    final leftover = sushiTakeUnseenHomeItems(slider, seen);
    expect(leftover.map(sushiHomeItemKey).toList(), ['6:1']);
  });

  test('for you pads from most watched then trending up to limit', () {
    final seen = <String>{};
    sushiTakeUnseenHomeItems([_item(1)], seen);
    final filled = sushiFillHomeRail(
      base: [_item(10), _item(1)],
      fillers: [_item(10), _item(20), _item(21), _item(30)],
      seen: seen,
      limit: 4,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['10:1', '20:1', '21:1', '30:1']);
  });

  test('empty for you still fills from rails', () {
    final seen = <String>{};
    final filled = sushiFillHomeRail(
      base: const [],
      fillers: [_item(2), _item(3)],
      seen: seen,
      limit: 16,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['2:1', '3:1']);
  });

  test('fill skips watched movies when asked', () {
    final seen = <String>{};
    final watched = _item(20);
    final filled = sushiFillHomeRail(
      base: [_item(10), watched],
      fillers: [watched, _item(21)],
      seen: seen,
      limit: 4,
      skip: (item) => sushiHomeItemKey(item) == '20:1',
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['10:1', '21:1']);
  });

  test('fill does not consume leftover fillers into seen', () {
    final seen = <String>{};
    final fillers = [_item(1), _item(2), _item(3), _item(4), _item(5)];
    final filled = sushiFillHomeRail(
      base: const [],
      fillers: fillers,
      seen: seen,
      limit: 2,
    );
    expect(filled.map(sushiHomeItemKey).toList(), ['1:1', '2:1']);
    expect(sushiTakeUnseenHomeItems(fillers, seen).map(sushiHomeItemKey).toList(), ['3:1', '4:1', '5:1']);
  });

  test('row unique across movie+series slider concat', () {
    final rows = sushiUniqueRows([
      _row(1),
      _row(2),
      _row(2),
      _row(2, kind: SushiKind.series),
      _row(3, kind: SushiKind.series),
    ]);
    expect(rows.map(sushiHomeRowKey).toList(), ['1:1', '2:1', '2:2', '3:2']);
  });

  List<ItemBaseModel> nItems(int start, int count) =>
      List.generate(count, (i) => _item(start + i));

  test('catalog rails keep a min floor instead of emptying into for you', () {
    final assembled = sushiAssembleHomeCatalogRails(
      seen: <String>{},
      forYouBase: [_item(1)],
      slider: nItems(10, 2),
      mostWatched: nItems(20, 18),
      trending: nItems(40, 18),
      seriesMostWatched: nItems(60, 18),
      seriesTrending: nItems(80, 18),
      minRailSize: 8,
    );
    expect(assembled.newest.length, 8);
    expect(assembled.mostWatched.length, greaterThanOrEqualTo(8));
    expect(assembled.trending.length, greaterThanOrEqualTo(8));
    expect(assembled.forYou.length, greaterThanOrEqualTo(8));
    final keys = [
      ...assembled.forYou,
      ...assembled.newest,
      ...assembled.mostWatched,
      ...assembled.trending,
      ...assembled.seriesMostWatched,
      ...assembled.seriesTrending,
    ].map(sushiHomeItemKey);
    expect(keys.length, keys.toSet().length);
  });

  test('for you drops watched movies even when they are the only fillers', () {
    final watched = _item(99);
    final assembled = sushiAssembleHomeCatalogRails(
      seen: <String>{},
      forYouBase: [watched, _item(1)],
      slider: nItems(10, 8),
      mostWatched: [watched, ...nItems(20, 10)],
      trending: nItems(40, 8),
      seriesMostWatched: const [],
      seriesTrending: const [],
      playedIds: {watched.id},
      minRailSize: 8,
    );
    expect(assembled.forYou.map(sushiHomeItemKey), isNot(contains('99:1')));
    expect(assembled.forYou.map(sushiHomeItemKey), contains('1:1'));
  });

  test('continue rail: in-progress local first, then follow, then rest local', () {
    final mid = _item(1).copyWith(
      userData: UserData(
        progress: 40,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(100),
      ),
    );
    final restLocal = _item(2).copyWith(
      userData: UserData(
        progress: 0,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(50),
      ),
    );
    final followNew = _item(3, kind: SushiKind.series);
    final followDup = _item(1, kind: SushiKind.movie); // same as mid — skipped
    final seen = <String>{};
    final rail = sushiAssembleContinueRail(
      [restLocal, mid],
      seen,
      follow: [followNew, followDup],
    );
    expect(rail.map(sushiHomeItemKey).toList(), ['1:1', '3:2', '2:1']);
  });
}
