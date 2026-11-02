import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';

bool sushiIsHomeLibraryEmpty({
  required ViewsModel views,
  required HomeModel dashboard,
}) {
  final allResume = [
    ...dashboard.resumeVideo,
    ...dashboard.resumeAudio,
    ...dashboard.resumeBooks,
  ];

  if (dashboard.activePrograms.isNotEmpty) return false;
  if (allResume.isNotEmpty) return false;
  if (dashboard.nextUp.isNotEmpty) return false;

  final hasRecentlyAdded = views.dashboardViews.any(
    (view) => view.collectionType != CollectionType.livetv && view.recentlyAdded.isNotEmpty,
  );
  if (hasRecentlyAdded) return false;

  return true;
}

/// Empty-library Seerr discover CTA removed — Sushi uses home rails instead.
class SushiDashboardEmptyHelpSliver extends ConsumerWidget {
  const SushiDashboardEmptyHelpSliver({
    required this.views,
    required this.dashboard,
    super.key,
  });

  final ViewsModel views;
  final HomeModel dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}
