import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/sushi/widgets/sushi_skeleton_box.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

bool sushiHomeDashboardHasCachedContent(HomeModel dashboard, ViewsModel views) {
  return sushiHomeHasCachedLists(views) || sushiHomeHasCachedSliderData(dashboard);
}

bool sushiHomeHasCachedLists(ViewsModel views) {
  return views.dashboardViews.any((view) => view.recentlyAdded.isNotEmpty);
}

bool sushiHomeHasCachedSliderData(HomeModel dashboard) {
  return dashboard.nextUp.isNotEmpty ||
      dashboard.resumeVideo.isNotEmpty ||
      dashboard.resumeAudio.isNotEmpty ||
      dashboard.resumeBooks.isNotEmpty ||
      dashboard.activePrograms.isNotEmpty;
}

bool sushiShowHomeBannerSkeleton({
  required bool homeBanner,
  required bool dashboardLoading,
  required bool dashboardLoaded,
  required bool carouselHasItems,
  required bool homeFullyReady,
  bool sliderCached = false,
  bool homeCached = false,
}) {
  if (!homeBanner) return false;
  if (carouselHasItems || sliderCached || homeCached) return false;
  if (!homeFullyReady) return true;
  if (carouselHasItems) return false;
  return dashboardLoading || !dashboardLoaded;
}

bool sushiHomeDashboardDataReady({
  required ViewsModel views,
  required HomeModel dashboard,
}) {
  return views.loaded && !views.loading && dashboard.loaded && !dashboard.loading;
}

/// Views + slider rails + watch later all settled — safe to reveal home rows without jump.
bool sushiHomeDashboardFullyReady({
  required WidgetRef ref,
  required ViewsModel views,
  required HomeModel dashboard,
}) {
  return dashboard.loaded && !dashboard.loading;
}

bool sushiShowHomeListSkeleton({
  required bool homeFullyReady,
  bool homeCached = false,
}) {
  
  if (homeCached) return false;
  return !homeFullyReady;
}

/// True when home shelves / slider may render (stale data OK while refreshing).
bool sushiHomeDashboardShowContent({
  required bool homeFullyReady,
  required bool homeCached,
}) {
  
  return homeFullyReady || homeCached;
}

/// Matches [HomeBannerWidget] / carousel / TV slider layout height to prevent home jump.
double sushiHomeBannerSkeletonHeight(BuildContext context, HomeBanner bannerType) {
  final maxHeight = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(125.0, 375.0);
  return switch (bannerType) {
    HomeBanner.tvSliderBanner => maxHeight * 1.3 + 32,
    HomeBanner.carousel => (AdaptiveLayout.of(context).isDesktop ? 6.0 : 10.0) + maxHeight + 24,
    HomeBanner.banner => maxHeight,
    HomeBanner.detailedBanner => maxHeight * 1.2 + 160,
    HomeBanner.hide => 0,
  };
}

/// Reserves home carousel / slider height while Next Up + resume data loads.
class SushiHomeBannerSkeleton extends StatelessWidget {
  final HomeBanner bannerType;

  const SushiHomeBannerSkeleton({required this.bannerType, super.key});

  @override
  Widget build(BuildContext context) {
    final maxHeight = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(125.0, 375.0);
    final reservedHeight = sushiHomeBannerSkeletonHeight(context, bannerType);
    final radius = BorderRadius.circular(
      bannerType == HomeBanner.detailedBanner ? 0 : 18,
    );

    if (bannerType == HomeBanner.detailedBanner) {
      final phoneOffset =
          AdaptiveLayout.viewSizeOf(context) <= ViewSize.phone ? MediaQuery.paddingOf(context).top + 80 : 0.0;
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topRight,
              child: Transform.translate(
                offset: Offset(0, -phoneOffset),
                child: FractionallySizedBox(
                  widthFactor: 0.85,
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: SushiSkeletonBox(borderRadius: radius),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SushiSkeletonBox(width: 220, height: 28, borderRadius: FladderTheme.defaultShape.borderRadius),
                const SizedBox(height: 12),
                SushiSkeletonBox(width: 160, height: 16, borderRadius: FladderTheme.defaultShape.borderRadius),
                const SizedBox(height: 16),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 5,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, __) => AspectRatio(
                      aspectRatio: 2 / 3,
                      child: SushiSkeletonBox(borderRadius: FladderTheme.defaultShape.borderRadius),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SizedBox(
      height: reservedHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: AdaptiveLayout.of(context).isDesktop ? 6 : 10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: bannerType == HomeBanner.tvSliderBanner ? 16 : 6,
              ),
              child: SushiSkeletonBox(
                height: bannerType == HomeBanner.tvSliderBanner ? maxHeight * 1.3 : maxHeight,
                borderRadius: bannerType == HomeBanner.tvSliderBanner
                    ? FladderTheme.largeShape.borderRadius
                    : radius,
              ),
            ),
          ),
          if (bannerType == HomeBanner.carousel) const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Horizontal poster row placeholder for home library shelves.
class SushiPosterRowSkeleton extends ConsumerWidget {
  final EdgeInsets contentPadding;
  final double aspectRatio;
  final int itemCount;

  const SushiPosterRowSkeleton({
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.aspectRatio = 2 / 3,
    this.itemCount = 6,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterSize = ref.watch(clientSettingsProvider.select((value) => value.posterSize));
    final rowHeight = ((AdaptiveLayout.poster(context).size * posterSize) /
            math.pow(aspectRatio, 0.55)) *
        0.72;
    final posterWidth = rowHeight * aspectRatio;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: contentPadding.copyWith(bottom: 8),
            child: SushiSkeletonBox(
              width: 140,
              height: 20,
              borderRadius: FladderTheme.defaultShape.borderRadius,
            ),
          ),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: contentPadding,
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, __) => SizedBox(
                width: posterWidth,
                child: SushiSkeletonBox(
                  borderRadius: FladderTheme.defaultShape.borderRadius,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
