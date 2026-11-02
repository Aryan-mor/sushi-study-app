import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/sushi/sushi_dashboard_empty_help.dart';
import 'package:fladder/sushi/sushi_dashboard_skeleton.dart';
import 'package:fladder/sushi/sushi_dashboard_watchlist.dart';
import 'package:fladder/sushi/sushi_home_detail_prefetch.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/providers/sushi_foryou_dashboard.dart';
import 'package:fladder/sushi/providers/sushi_not_interested.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_tv_ui_limits.dart';
import 'package:fladder/sushi/sushi_view_labels.dart';
import 'package:fladder/providers/dashboard_mode_provider.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/home_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/dashboard/home_banner_widget.dart';
import 'package:fladder/screens/dashboard/music_dashboard_screen.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/screens/shared/nested_sliver_appbar.dart';
import 'package:fladder/sushi/providers/sushi_home_rails_provider.dart';
import 'package:fladder/sushi/sushi_initbot_transport.dart';
import 'package:fladder/sushi/sushi_views.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/sliver_list_padding.dart';
import 'package:fladder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:fladder/widgets/shared/pinch_poster_zoom.dart';
import 'package:fladder/widgets/shared/poster_size_slider.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _timer;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  final textController = TextEditingController();

  final selectedPoster = ValueNotifier<ItemBaseModel?>(null);

  @override
  void initState() {
    super.initState();
    // Cold-start half of bot rotation (docs/02 §7): re-syncs the Assignment's API/delivery bot
    // lists in the background, in case they changed since this session last asked. No-op past
    // the first call in a process (dashboard can rebuild/remount many times).
    sushiRefreshInitbotOnColdStart(onReady: () {
      if (!mounted) return;
      unawaited(ref.read(dashboardProvider.notifier).fetchNextUpAndResume(force: true));
    });
    // Skip 120s SWR refresh: each refresh is a Telegram bot round-trip, and DashboardScreen
    // stays mounted under pushed detail/player screens for the whole session.
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Sushi's catalog rails (New/For You) aren't backed by a real Jellyfin folder, so "show more"
  /// opens the closest synthetic library view (Movies or Series, picked by whichever kind
  /// dominates the row) instead of a rail-specific listing.
  LibrarySearchRoute _catalogRailRoute(List<ItemBaseModel> posters) {
    return LibrarySearchRoute(
      viewModelId: posters.getMostCommonType == FladderItemType.series ? sushiViewSeries : sushiViewMovies,
      recursive: true,
    );
  }

  /// Trending / Most watched rails now have a real backend ordering (LIST_SORT_TRENDING /
  /// LIST_SORT_MOST_WATCHED): rails-materialised items first in rail rank order, newest-first
  /// after that (docs/12 §2, the `rails` table is a capped top-N, not a full ranking).
  LibrarySearchRoute _rankedRailRoute(String viewModelId, SortingOptions sort) {
    return LibrarySearchRoute(
      viewModelId: viewModelId,
      sortingOptions: sort,
      sortOrder: SortingOrder.descending,
      recursive: true,
    );
  }

  Future<void> _refreshHome() async {
    if (!mounted) return;
    // Sushi has no HTTP API — updateInformation()/SushiHomeRefresh both assume a Jellyfin-style
    // server and would throw (no host to resolve). Its own home fetch is enough.
    await ref.read(dashboardProvider.notifier).fetchNextUpAndResume(force: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sushiNotInterestedProvider);
    if (ref.watch(musicDashboardModeProvider)) {
      return const MusicDashboardScreen();
    }

    final padding = AdaptiveLayout.adaptivePadding(context);
    final bannerType = ref.watch(homeSettingsProvider.select((value) => value.homeBanner));
    final dashboardData = ref.watch(dashboardProvider);
    final views = ref.watch(viewsProvider);
    final homeSettings = ref.watch(homeSettingsProvider);
    final homeBanner = ref.watch(homeSettingsProvider.select((value) => value.homeBanner)) != HomeBanner.hide;
    final hiddenHome = ref.watch(sushiNotInterestedProvider);
    final resumeVideo = sushiDropNotInterested(dashboardData.resumeVideo, hiddenHome);
    final resumeAudio = sushiDropNotInterested(dashboardData.resumeAudio, hiddenHome);
    final resumeBooks = sushiDropNotInterested(dashboardData.resumeBooks, hiddenHome);
    final tvChannels = dashboardData.activePrograms;
    final sushiRailsRaw = ref.watch(sushiHomeRailsProvider);
    final sushiRails = SushiHomeRailsData(
      slider: sushiDropNotInterested(sushiRailsRaw.slider, hiddenHome),
      mostWatched: sushiDropNotInterested(sushiRailsRaw.mostWatched, hiddenHome),
      trending: sushiDropNotInterested(sushiRailsRaw.trending, hiddenHome),
      seriesMostWatched: sushiDropNotInterested(sushiRailsRaw.seriesMostWatched, hiddenHome),
      seriesTrending: sushiDropNotInterested(sushiRailsRaw.seriesTrending, hiddenHome),
    );

    final allResume = [...resumeVideo, ...resumeAudio, ...resumeBooks].toList();

    final homeCarouselItems = sushiAssembleHomeCarousel(
      settings: homeSettings.carouselSettings,
      nextUp: sushiDropNotInterested(dashboardData.nextUp, hiddenHome),
      resume: allResume,
      trendingMovies: sushiRails.trending,
      trendingSeries: sushiRails.seriesTrending,
    );
    final homeBannerPosters = SushiTvUiLimits.shouldCapHomeSlider(ref)
        ? SushiTvUiLimits.capHomeSliderItems(homeCarouselItems)
        : SushiHomeDetailPrefetch.capSliderItems(homeCarouselItems);

    final viewSize = AdaptiveLayout.viewSizeOf(context);

    final useTVExpandedLayout = ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final homeCached = sushiHomeDashboardHasCachedContent(dashboardData, views);
    final sliderCached = sushiHomeHasCachedSliderData(dashboardData);
    final sushiHasRails = sushiRails.hasAny;
    final homeFullyReady = (dashboardData.loaded && !dashboardData.loading) || sushiHasRails;
    final homeShowContent = homeFullyReady;
    final showBannerSkeleton = sushiShowHomeBannerSkeleton(
      homeBanner: homeBanner,
      dashboardLoading: dashboardData.loading,
      dashboardLoaded: dashboardData.loaded,
      carouselHasItems: homeCarouselItems.isNotEmpty,
      homeFullyReady: homeFullyReady,
      sliderCached: sliderCached,
      homeCached: homeCached,
    );
    final showBanner = homeBanner &&
        homeShowContent &&
        (sliderCached || (dashboardData.loaded && !dashboardData.loading)) &&
        homeCarouselItems.isNotEmpty;
    final showListSkeleton = !sushiHasRails && (!dashboardData.loaded || dashboardData.loading);

    // R-RAIL-1: item once on home. Banner lead → continue (no min) → catalog rails (min floor).
    // Only the first banner slide is removed from the rails it belongs to. Later slides stay.
    final homeSeen = <String>{};
    if (showBanner) {
      sushiTakeUnseenHomeItems(sushiHomeBannerExcluded(homeBannerPosters), homeSeen);
    }
    final forYouAsync = ref.watch(sushiForYouDashboardProvider);
    final forYouLoading = forYouAsync.isLoading && !forYouAsync.hasValue;
    final forYouSource = forYouLoading
        ? const <ItemBaseModel>[]
        : sushiDropNotInterested(forYouAsync.valueOrNull?.items ?? const [], hiddenHome);
    final continueWatchingPosters = sushiAssembleContinueRail(resumeVideo, homeSeen);
    final continueListeningPosters = sushiAssembleContinueRail(resumeAudio, homeSeen);
    final continueReadingPosters = sushiAssembleContinueRail(resumeBooks, homeSeen);

    final playedIds = ref.watch(sushiCatalogItemFlagsProvider.select((s) => s.playedIds));
    final catalogRails = sushiAssembleHomeCatalogRails(
      seen: homeSeen,
      forYouBase: forYouSource,
      slider: sushiRails.slider,
      mostWatched: sushiRails.mostWatched,
      trending: sushiRails.trending,
      seriesMostWatched: sushiRails.seriesMostWatched,
      seriesTrending: sushiRails.seriesTrending,
      playedIds: playedIds,
      fillForYou: !forYouLoading,
    );
    final forYouPosters = catalogRails.forYou;
    final newPosters = catalogRails.newest;
    final mostWatchedPosters = catalogRails.mostWatched;
    final trendingPosters = catalogRails.trending;
    final seriesMostWatchedPosters = catalogRails.seriesMostWatched;
    final seriesTrendingPosters = catalogRails.seriesTrending;

    return NestedScaffold(
      background: ValueListenableBuilder<ItemBaseModel?>(
        valueListenable: selectedPoster,
        builder: (_, value, __) {
          return BackgroundImage(
            images: (value != null
                    ? [value]
                    : [
                        ...homeCarouselItems,
                        ...dashboardData.nextUp,
                        ...allResume,
                      ])
                .map((e) => e.images)
                .nonNulls
                .toList(),
          );
        },
      ),
      body: PullToRefresh(
        refreshKey: _refreshIndicatorKey,
        displacement: 80 + MediaQuery.of(context).viewPadding.top,
        refreshOnStart: false,
        onRefresh: () async => await _refreshHome(),
        child: (context) => PinchPosterZoom(
          scaleDifference: (difference) => ref.read(clientSettingsProvider.notifier).addPosterSize(difference),
          child: CustomScrollView(
            controller: AdaptiveLayout.scrollOf(context, HomeTabs.dashboard),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (bannerType != HomeBanner.detailedBanner) const DefaultSliverTopBadding(),
              if (viewSize == ViewSize.phone)
                NestedSliverAppBar(
                  route: LibrarySearchRoute(),
                  parent: context,
                ),
              if (showBannerSkeleton || showBanner)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: AdaptiveLayout.adaptivePadding(
                      context,
                      horizontalPadding: 0,
                    ),
                    child: AnimatedCrossFade(
                      duration: const Duration(milliseconds: 250),
                      sizeCurve: Curves.easeOutCubic,
                      firstCurve: Curves.easeOut,
                      secondCurve: Curves.easeIn,
                      crossFadeState: showBanner ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                      firstChild: SushiHomeBannerSkeleton(bannerType: bannerType),
                      secondChild: showBanner
                          ? HomeBannerWidget(
                              posters: homeBannerPosters,
                              onSelect: (poster) => selectedPoster.value = poster,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (AdaptiveLayout.of(context).isDesktop)
                const SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PosterSizeWidget(),
                    ],
                  ),
                ),
              SushiDashboardEmptyHelpSliver(
                views: views,
                dashboard: dashboardData,
              ),
              if (showListSkeleton) ...[
                SliverToBoxAdapter(
                  child: SushiPosterRowSkeleton(contentPadding: padding),
                ),
                SliverToBoxAdapter(
                  child: SushiPosterRowSkeleton(contentPadding: padding),
                ),
              ],
              if (homeShowContent)
                ...[
                  if (tvChannels.isNotEmpty)
                    PosterRow(
                      contentPadding: padding,
                      tvMode: useTVExpandedLayout,
                      label: context.localized.activeTvChannels,
                      collectionAspectRatio: 0.55,
                      onLabelClick: () {
                        return LiveTvRoute().navigate(context);
                      },
                      posters: tvChannels,
                    ),
                  if (continueWatchingPosters.isNotEmpty &&
                      (homeSettings.nextUp == HomeNextUp.cont || homeSettings.nextUp == HomeNextUp.separate))
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.dashboardContinueWatching,
                      sushiContinueToggle: true,
                      posters: continueWatchingPosters,
                    ),
                  if (forYouLoading)
                    SushiPosterRowSkeleton(contentPadding: padding)
                  else if (forYouPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.sushiForYou,
                      sushiContinueToggle: true,
                      posters: forYouPosters,
                      onLabelClick: () => context.router.push(_catalogRailRoute(forYouPosters)),
                    ),
                  if (continueListeningPosters.isNotEmpty &&
                      (homeSettings.nextUp == HomeNextUp.cont || homeSettings.nextUp == HomeNextUp.separate))
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.dashboardContinueListening,
                      posters: continueListeningPosters,
                    ),
                  if (continueReadingPosters.isNotEmpty &&
                      (homeSettings.nextUp == HomeNextUp.cont || homeSettings.nextUp == HomeNextUp.separate))
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.dashboardContinueReading,
                      posters: continueReadingPosters,
                    ),
                  if (newPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.sushiHomeNew,
                      sushiContinueToggle: true,
                      posters: newPosters,
                      onLabelClick: () => context.router.push(_catalogRailRoute(newPosters)),
                    ),
                  if (mostWatchedPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.sushiHomeMostWatched,
                      sushiContinueToggle: true,
                      posters: mostWatchedPosters,
                      onLabelClick: () =>
                          context.router.push(_rankedRailRoute(sushiViewMovies, SortingOptions.mostWatched)),
                    ),
                  if (trendingPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.trending,
                      sushiContinueToggle: true,
                      posters: trendingPosters,
                      onLabelClick: () =>
                          context.router.push(_rankedRailRoute(sushiViewMovies, SortingOptions.trending)),
                    ),
                  if (seriesMostWatchedPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.sushiHomeSeriesSection(context.localized.sushiHomeMostWatched),
                      sushiContinueToggle: true,
                      posters: seriesMostWatchedPosters,
                      onLabelClick: () =>
                          context.router.push(_rankedRailRoute(sushiViewSeries, SortingOptions.mostWatched)),
                    ),
                  if (seriesTrendingPosters.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      label: context.localized.sushiHomeSeriesSection(context.localized.trending),
                      sushiContinueToggle: true,
                      posters: seriesTrendingPosters,
                      onLabelClick: () =>
                          context.router.push(_rankedRailRoute(sushiViewSeries, SortingOptions.trending)),
                    ),
                  ...sushiDashboardRecentlyAddedRows(
                    context: context,
                    ref: ref,
                    views: views,
                    padding: padding,
                    useTVExpandedLayout: useTVExpandedLayout,
                    defaultRows: views.dashboardViews
                        .where(
                          (element) =>
                              element.recentlyAdded.isNotEmpty && element.collectionType != CollectionType.livetv,
                        )
                        .map(
                          (view) => PosterRow(
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
                            posters: view.recentlyAdded,
                          ),
                        ),
                  ),
                ]
                    .nonNulls
                    .toList()
                    .mapIndexed(
                      (index, child) => SliverToBoxAdapter(
                        child: FocusProvider(
                          autoFocus: homeCarouselItems.isEmpty ? index == 0 : false,
                          child: child,
                        ),
                      ),
                    )
                    .toList()
                    .addInBetween(
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 16),
                      ),
                    ),
              const DefaultSliverBottomPadding(),
            ],
          ),
        ),
      ),
    );
  }
}
