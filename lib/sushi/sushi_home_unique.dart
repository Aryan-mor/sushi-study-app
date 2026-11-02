import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';

/// Matches backend [rails.Policy.MinRailSize]. Continue watching has no floor.
const sushiHomeMinRailSize = 8;

/// Personalized For You cap. Floor is still [sushiHomeMinRailSize].
const sushiHomeForYouLimit = 16;

/// Home identity for R-RAIL-1. TMDB+kind, not [ItemBaseModel.id] — that id drops kind, so
/// movie 550 and series 550 would collapse.
String sushiHomeItemKey(ItemBaseModel item) {
  final identity = sushiContinueIdentity(item);
  if (identity != null) {
    return '${identity.tmdbId}:${sushiKindToWire(identity.kind)}';
  }
  return item.id;
}

String sushiHomeRowKey(SushiRow row) => '${row.tmdbId}:${sushiKindToWire(row.kind)}';

/// First occurrence wins. Mutates [seen]. Stops at [limit] so leftovers stay available for later rails.
List<ItemBaseModel> sushiTakeUnseenHomeItems(
  Iterable<ItemBaseModel> items,
  Set<String> seen, {
  int? limit,
}) {
  final out = <ItemBaseModel>[];
  for (final item in items) {
    if (limit != null && out.length >= limit) break;
    if (seen.add(sushiHomeItemKey(item))) out.add(item);
  }
  return out;
}

/// Personalized [base] first, then [fillers] (most watched / trending) up to [limit]. Mutates [seen].
List<ItemBaseModel> sushiFillHomeRail({
  required Iterable<ItemBaseModel> base,
  required Iterable<ItemBaseModel> fillers,
  required Set<String> seen,
  required int limit,
  bool Function(ItemBaseModel item)? skip,
}) {
  final native = skip == null ? base : base.where((item) => !skip(item));
  final out = sushiTakeUnseenHomeItems(native, seen, limit: limit);
  if (out.length >= limit) return out;
  final extra = skip == null ? fillers : fillers.where((item) => !skip(item));
  out.addAll(sushiTakeUnseenHomeItems(extra, seen, limit: limit - out.length));
  return out;
}

List<ItemBaseModel> sushiUniqueHomeItems(Iterable<ItemBaseModel> items) {
  return sushiTakeUnseenHomeItems(items, <String>{});
}

/// Mid-watch on a home card (local continue store paints progress into userData).
bool sushiHomeItemInProgress(ItemBaseModel item) {
  final p = item.userData.progress;
  return p >= 5 && p < 90;
}

/// Continue-watching row. Unique, no floor. Keeps titles already on the banner — slider overlap
/// is the exception to R-RAIL-1. Still records keys in [seen] so catalog rails drop them.
///
/// Order: in-progress first (newest activity first), then [follow] (server already sorted
/// in-progress → newest unfinished ep), then remaining local rows newest→oldest.
List<ItemBaseModel> sushiAssembleContinueRail(
  Iterable<ItemBaseModel> resume,
  Set<String> seen, {
  Iterable<ItemBaseModel> follow = const [],
  int? limit,
}) {
  final local = resume.toList();
  final mid = <ItemBaseModel>[];
  final restLocal = <ItemBaseModel>[];
  for (final item in local) {
    if (sushiHomeItemInProgress(item)) {
      mid.add(item);
    } else {
      restLocal.add(item);
    }
  }
  int byLastPlayed(ItemBaseModel a, ItemBaseModel b) {
    final aAt = a.userData.lastPlayed?.millisecondsSinceEpoch ?? 0;
    final bAt = b.userData.lastPlayed?.millisecondsSinceEpoch ?? 0;
    return bAt.compareTo(aAt);
  }

  mid.sort(byLastPlayed);
  restLocal.sort(byLastPlayed);

  // Dedupe inside this rail only. Banner overlap is allowed (R-RAIL-1 exception); we still
  // record keys into [seen] so later catalog rails drop them.
  final outKeys = <String>{};
  final out = <ItemBaseModel>[];
  void take(Iterable<ItemBaseModel> items) {
    for (final item in items) {
      if (limit != null && out.length >= limit) return;
      final key = sushiHomeItemKey(item);
      if (!outKeys.add(key)) continue;
      out.add(item);
      seen.add(key);
    }
  }

  take(mid);
  take(follow);
  take(restLocal);
  return out;
}

ItemBaseModel? sushiFirstHomeItemOfType(Iterable<ItemBaseModel> items, FladderItemType type) {
  for (final item in items) {
    if (item.type == type) return item;
  }
  return null;
}

List<SushiRow> sushiUniqueRows(Iterable<SushiRow> rows) {
  final seen = <String>{};
  final out = <SushiRow>[];
  for (final row in rows) {
    if (seen.add(sushiHomeRowKey(row))) out.add(row);
  }
  return out;
}

/// Only the lead banner slide is hidden from the rails it also belongs to (trending, continue
/// watching, New, …). Every later slide stays on those rails.
List<ItemBaseModel> sushiHomeBannerExcluded(Iterable<ItemBaseModel> banner) {
  final it = banner.iterator;
  if (!it.moveNext()) return const [];
  return [it.current];
}

/// Banner list. Unique across sources (resume + slider). Carousel viewport clones stay in the
/// widget, not here.
///
/// Slide 1 = trendiest movie, slide 2 = trendiest series (TMDB week rails, then catalog slider).
/// Resume-only carousels stay resume order.
List<ItemBaseModel> sushiAssembleHomeCarousel({
  required HomeCarouselSettings settings,
  required List<ItemBaseModel> nextUp,
  required List<ItemBaseModel> resume,
  List<ItemBaseModel> trendingMovies = const [],
  List<ItemBaseModel> trendingSeries = const [],
}) {
  final raw = switch (settings) {
    HomeCarouselSettings.nextUp => nextUp,
    HomeCarouselSettings.combined => [...resume, ...nextUp],
    HomeCarouselSettings.cont => resume,
  };
  if (settings == HomeCarouselSettings.cont) {
    return sushiUniqueHomeItems(raw);
  }
  final pinMovie = sushiFirstHomeItemOfType(trendingMovies, FladderItemType.movie) ??
      sushiFirstHomeItemOfType(nextUp, FladderItemType.movie) ??
      (settings == HomeCarouselSettings.combined
          ? sushiFirstHomeItemOfType(resume, FladderItemType.movie)
          : null);
  final pinSeries = sushiFirstHomeItemOfType(trendingSeries, FladderItemType.series) ??
      sushiFirstHomeItemOfType(nextUp, FladderItemType.series) ??
      (settings == HomeCarouselSettings.combined
          ? sushiFirstHomeItemOfType(resume, FladderItemType.series)
          : null);
  return sushiUniqueHomeItems([
    if (pinMovie != null) pinMovie,
    if (pinSeries != null) pinSeries,
    ...raw,
  ]);
}

/// Catalog home rows after banner + continue watching. Unique (R-RAIL-1). Every row except
/// continue watching is filled to [minRailSize] from other rails' surplus. For You never
/// includes movies this viewer already watched.
class SushiHomeCatalogRails {
  const SushiHomeCatalogRails({
    required this.forYou,
    required this.newest,
    required this.mostWatched,
    required this.trending,
    required this.seriesMostWatched,
    required this.seriesTrending,
  });

  final List<ItemBaseModel> forYou;
  final List<ItemBaseModel> newest;
  final List<ItemBaseModel> mostWatched;
  final List<ItemBaseModel> trending;
  final List<ItemBaseModel> seriesMostWatched;
  final List<ItemBaseModel> seriesTrending;
}

bool sushiHomeIsWatchedMovie(ItemBaseModel item, Set<String> playedIds) {
  if (item.type != FladderItemType.movie) return false;
  return item.userData.played || playedIds.contains(item.id);
}

SushiHomeCatalogRails sushiAssembleHomeCatalogRails({
  required Set<String> seen,
  required Iterable<ItemBaseModel> forYouBase,
  required Iterable<ItemBaseModel> slider,
  required Iterable<ItemBaseModel> mostWatched,
  required Iterable<ItemBaseModel> trending,
  required Iterable<ItemBaseModel> seriesMostWatched,
  required Iterable<ItemBaseModel> seriesTrending,
  Set<String> playedIds = const {},
  int minRailSize = sushiHomeMinRailSize,
  int forYouLimit = sushiHomeForYouLimit,
  bool fillForYou = true,
}) {
  bool skipWatchedMovie(ItemBaseModel item) => sushiHomeIsWatchedMovie(item, playedIds);

  final forYou = sushiTakeUnseenHomeItems(
    forYouBase.where((item) => !skipWatchedMovie(item)),
    seen,
    limit: forYouLimit,
  );
  final newest = sushiTakeUnseenHomeItems(slider, seen);
  final most = sushiTakeUnseenHomeItems(mostWatched, seen);
  final trend = sushiTakeUnseenHomeItems(trending, seen);
  final seriesMost = sushiTakeUnseenHomeItems(seriesMostWatched, seen);
  final seriesTrend = sushiTakeUnseenHomeItems(seriesTrending, seen);

  // Steal extras from later catalog rails first so New / Most watched keep native cards.
  // For You never donates — followed series stay on For You. Movie rows do not take series
  // cards, and series rows do not take movies.
  final catalogSteal = [seriesTrend, seriesMost, trend, most, newest];
  sushiStealHomeRailToMin(dest: newest, donors: catalogSteal, min: minRailSize);
  sushiStealHomeRailToMin(
    dest: most,
    donors: catalogSteal,
    min: minRailSize,
    skip: (item) => item.type == FladderItemType.series,
  );
  sushiStealHomeRailToMin(
    dest: trend,
    donors: catalogSteal,
    min: minRailSize,
    skip: (item) => item.type == FladderItemType.series,
  );
  sushiStealHomeRailToMin(
    dest: seriesMost,
    donors: catalogSteal,
    min: minRailSize,
    skip: (item) => item.type == FladderItemType.movie,
  );
  sushiStealHomeRailToMin(
    dest: seriesTrend,
    donors: catalogSteal,
    min: minRailSize,
    skip: (item) => item.type == FladderItemType.movie,
  );
  if (fillForYou) {
    sushiStealHomeRailToMin(
      dest: forYou,
      donors: catalogSteal,
      min: minRailSize,
      skip: skipWatchedMovie,
    );
  }

  return SushiHomeCatalogRails(
    forYou: forYou,
    newest: newest,
    mostWatched: most,
    trending: trend,
    seriesMostWatched: seriesMost,
    seriesTrending: seriesTrend,
  );
}

/// Move cards past [min] on [donors] onto [dest] until [dest] reaches [min]. Never drains a
/// donor below [min]. Mutates the lists.
void sushiStealHomeRailToMin({
  required List<ItemBaseModel> dest,
  required List<List<ItemBaseModel>> donors,
  required int min,
  bool Function(ItemBaseModel item)? skip,
}) {
  while (dest.length < min) {
    var moved = false;
    for (final donor in donors) {
      if (identical(donor, dest)) continue;
      if (donor.length <= min) continue;
      for (var i = donor.length - 1; i >= min; i--) {
        final item = donor[i];
        if (skip != null && skip(item)) continue;
        donor.removeAt(i);
        dest.add(item);
        moved = true;
        break;
      }
      if (moved) break;
    }
    if (!moved) return;
  }
}
