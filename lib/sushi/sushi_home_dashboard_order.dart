import 'package:flutter/widgets.dart';

import 'package:fladder/util/localization_helper.dart';

/// Virtual OrderedViews ids for OX-only home dashboard rows (not Jellyfin library folders).
abstract final class SushiHomeDashboardOrder {
  static const tvViewId = '00000000-0000-0000-0000-000000000002';
  static const forYouId = '00000000-0000-0000-0000-000000000005';
  static const watchLaterId = '00000000-0000-0000-0000-000000000006';
  static const favoritesId = '00000000-0000-0000-0000-000000000007';

  static const dashboardRowIds = [forYouId, watchLaterId, favoritesId];

  static bool isDashboardRowId(String id) =>
      id == forYouId || id == watchLaterId || id == favoritesId;

  static String? label(BuildContext context, String id) {
    return switch (id) {
      forYouId => context.localized.sushiForYou,
      watchLaterId => context.localized.sushiWatchlist,
      favoritesId => context.localized.favorites,
      _ => null,
    };
  }

  /// Library folder ids plus dashboard rows for the home-order editor. Order matters here: watch
  /// later is placed first (against tvView), then for-you slots in just ahead of it, then
  /// favorites just after it -- giving tvView, forYou, watchLater, favorites.
  static List<String> allOrderableIds(List<String> libraryIds) {
    final out = <String>[...libraryIds];
    _insertRowIfMissing(out, watchLaterId);
    _insertRowIfMissing(out, forYouId);
    _insertRowIfMissing(out, favoritesId);
    return out;
  }

  static void _insertRowIfMissing(List<String> out, String rowId) {
    if (out.contains(rowId)) return;
    if (rowId == favoritesId) {
      final watchLaterIndex = out.indexOf(watchLaterId);
      if (watchLaterIndex >= 0) {
        out.insert(watchLaterIndex + 1, rowId);
        return;
      }
    }
    if (rowId == forYouId) {
      final watchLaterIndex = out.indexOf(watchLaterId);
      if (watchLaterIndex >= 0) {
        out.insert(watchLaterIndex, rowId);
        return;
      }
    }
    if (rowId == watchLaterId || rowId == forYouId) {
      final tvIndex = out.indexOf(tvViewId);
      out.insert(tvIndex >= 0 ? tvIndex + 1 : out.length, rowId);
      return;
    }
    out.add(rowId);
  }
}
