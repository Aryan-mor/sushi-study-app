import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/sushi/sushi_home_dashboard_order.dart';
import 'package:fladder/sushi/sushi_view_labels.dart';
import 'package:fladder/sushi/sushi_dashboard_skeleton.dart';
import 'package:fladder/sushi/providers/sushi_favorites_dashboard.dart';
import 'package:fladder/sushi/providers/sushi_not_interested.dart';
import 'package:fladder/sushi/providers/sushi_watchlist_dashboard.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/localization_helper.dart';

Iterable<Widget> sushiDashboardRecentlyAddedRows({
  required BuildContext context,
  required WidgetRef ref,
  required ViewsModel views,
  required EdgeInsets padding,
  required bool useTVExpandedLayout,
  required Iterable<Widget> defaultRows,
}) {
  

  final user = ref.read(userProvider);
  final excludes = user?.latestItemsExcludes ?? const [];
  final configuredOrder = user?.userConfiguration?.orderedViews ?? const [];
  final order = configuredOrder.isNotEmpty
      ? configuredOrder
      : SushiHomeDashboardOrder.allOrderableIds(views.dashboardViews.map((v) => v.id).toList());

  final viewById = {for (final view in views.dashboardViews) view.id: view};
  final rows = <Widget>[];
  final placedViewIds = <String>{};

  for (final id in order) {
    if (excludes.contains(id)) continue;

    if (id == SushiHomeDashboardOrder.forYouId) {
      // DashboardScreen paints the For You rail itself (after Continue Watching).
      continue;
    }
    if (id == SushiHomeDashboardOrder.watchLaterId) {
      rows.add(
        SushiWatchLaterPosterRow(
          contentPadding: padding,
          tvMode: useTVExpandedLayout,
          views: views,
        ),
      );
      continue;
    }
    if (id == SushiHomeDashboardOrder.favoritesId) {
      rows.add(
        SushiFavoritesPosterRow(
          contentPadding: padding,
          tvMode: useTVExpandedLayout,
        ),
      );
      continue;
    }

    final view = viewById[id];
    if (view == null) continue;
    placedViewIds.add(id);
    final row = _libraryRecentlyAddedRow(
      context: context,
      ref: ref,
      view: view,
      padding: padding,
      useTVExpandedLayout: useTVExpandedLayout,
    );
    if (row != null) rows.add(row);
  }

  for (final view in views.dashboardViews) {
    if (placedViewIds.contains(view.id) || excludes.contains(view.id)) continue;
    final row = _libraryRecentlyAddedRow(
      context: context,
      ref: ref,
      view: view,
      padding: padding,
      useTVExpandedLayout: useTVExpandedLayout,
    );
    if (row != null) rows.add(row);
  }

  return rows;
}

Widget? _libraryRecentlyAddedRow({
  required BuildContext context,
  required WidgetRef ref,
  required ViewModel view,
  required EdgeInsets padding,
  required bool useTVExpandedLayout,
}) {
  if (view.recentlyAdded.isEmpty || view.collectionType == CollectionType.livetv) {
    return null;
  }
  final posters = sushiDropNotInterested(view.recentlyAdded, ref.watch(sushiNotInterestedProvider));
  if (posters.isEmpty) return null;
  return PosterRow(
    tvMode: useTVExpandedLayout,
    contentPadding: padding,
    label: context.localized.dashboardRecentlyAdded(sushiSyntheticViewLabel(context, view)),
    collectionAspectRatio: view.collectionType.aspectRatio,
    onLabelClick: () {
      if (view.collectionType == CollectionType.livetv) {
        return LiveTvRoute().navigate(context);
      }
      return context.router.push(
        LibrarySearchRoute(
          viewModelId: view.id,
          types: switch (view.collectionType) {
            CollectionType.tvshows => {
                FladderItemType.episode: true,
              },
            _ => {},
          },
          sortingOptions: switch (view.collectionType) {
            CollectionType.books ||
            CollectionType.boxsets ||
            CollectionType.folders ||
            CollectionType.music =>
              SortingOptions.dateLastContentAdded,
            _ => SortingOptions.dateAdded,
          },
          sortOrder: SortingOrder.descending,
          recursive: true,
        ),
      );
    },
    posters: posters,
  );
}

class SushiFavoritesPosterRow extends ConsumerWidget {
  const SushiFavoritesPosterRow({
    required this.contentPadding,
    required this.tvMode,
    super.key,
  });

  final EdgeInsets contentPadding;
  final bool tvMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(sushiNotInterestedProvider);

    if (ref.watch(sushiFavoritesFeedHandledProvider)) {
      final data = ref.watch(sushiFavoritesDashboardFeedProvider) ?? SushiFavoritesDashboardData.empty;
      final items = sushiDropNotInterested(data.items, hidden);
      if (items.isEmpty) return const SizedBox.shrink();
      return _favoritesPosterRow(context, items);
    }

    final cachedFeed = ref.watch(sushiFavoritesDashboardFeedProvider);
    if (cachedFeed != null && cachedFeed.items.isNotEmpty) {
      final items = sushiDropNotInterested(cachedFeed.items, hidden);
      if (items.isEmpty) return const SizedBox.shrink();
      return _favoritesPosterRow(context, items);
    }

    final favoritesAsync = ref.watch(sushiFavoritesDashboardProvider);
    return favoritesAsync.when(
      data: (data) {
        final items = sushiDropNotInterested(data.items, hidden);
        if (items.isEmpty) return const SizedBox.shrink();
        return _favoritesPosterRow(context, items);
      },
      loading: () => SushiPosterRowSkeleton(contentPadding: contentPadding),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _favoritesPosterRow(BuildContext context, List<ItemBaseModel> items) {
    return PosterRow(
      tvMode: tvMode,
      contentPadding: contentPadding,
      label: context.localized.favorites,
      onLabelClick: () => context.router.push(const FavouritesRoute()),
      posters: items,
    );
  }
}

class SushiWatchLaterPosterRow extends ConsumerWidget {
  const SushiWatchLaterPosterRow({
    required this.contentPadding,
    required this.tvMode,
    required this.views,
    super.key,
  });

  final EdgeInsets contentPadding;
  final bool tvMode;
  final ViewsModel views;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(sushiNotInterestedProvider);

    if (ref.watch(sushiWatchlistFeedHandledProvider)) {
      final data = ref.watch(sushiWatchlistDashboardFeedProvider) ?? SushiWatchlistDashboardData.empty;
      final items = sushiDropNotInterested(data.items, hidden);
      if (items.isEmpty) return const SizedBox.shrink();
      final playlistsView = views.dashboardViews.firstWhereOrNull(
        (view) => view.collectionType == CollectionType.playlists,
      );
      return PosterRow(
        tvMode: tvMode,
        contentPadding: contentPadding,
        label: context.localized.sushiWatchlist,
        onLabelClick: data.playlistId == null || playlistsView == null
            ? null
            : () {
                context.router.push(
                  LibrarySearchRoute(
                    viewModelId: playlistsView.id,
                    folderId: [data.playlistId!],
                  ),
                );
              },
        posters: items,
      );
    }

    final cachedFeed = ref.watch(sushiWatchlistDashboardFeedProvider);
    if (cachedFeed != null && cachedFeed.items.isNotEmpty) {
      final items = sushiDropNotInterested(cachedFeed.items, hidden);
      if (items.isEmpty) return const SizedBox.shrink();
      final playlistsView = views.dashboardViews.firstWhereOrNull(
        (view) => view.collectionType == CollectionType.playlists,
      );
      return PosterRow(
        tvMode: tvMode,
        contentPadding: contentPadding,
        label: context.localized.sushiWatchlist,
        onLabelClick: cachedFeed.playlistId == null || playlistsView == null
            ? null
            : () {
                context.router.push(
                  LibrarySearchRoute(
                    viewModelId: playlistsView.id,
                    folderId: [cachedFeed.playlistId!],
                  ),
                );
              },
        posters: items,
      );
    }

    final watchlistAsync = ref.watch(sushiWatchlistDashboardProvider);
    return watchlistAsync.when(
      data: (data) {
        final items = sushiDropNotInterested(data.items, hidden);
        if (items.isEmpty) return const SizedBox.shrink();
        final playlistsView = views.dashboardViews.firstWhereOrNull(
          (view) => view.collectionType == CollectionType.playlists,
        );
        return PosterRow(
          tvMode: tvMode,
          contentPadding: contentPadding,
          label: context.localized.sushiWatchlist,
          onLabelClick: data.playlistId == null || playlistsView == null
              ? null
              : () {
                  context.router.push(
                    LibrarySearchRoute(
                      viewModelId: playlistsView.id,
                      folderId: [data.playlistId!],
                    ),
                  );
                },
          posters: items,
        );
      },
      loading: () => SushiPosterRowSkeleton(contentPadding: contentPadding),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
