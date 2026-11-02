import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';

DestinationModel _tab(String label, PageRouteInfo route) =>
    DestinationModel(label: label, icon: const Icon(Icons.circle), selectedIcon: const Icon(Icons.circle), route: route);

void main() {
  test('My videos sits just above Synced', () {
    final tabs = [
      _tab('Dashboard', const DashboardRoute()),
      _tab('Favorites', const FavouritesRoute()),
      _tab('Watch later', const WatchLaterRoute()),
      _tab('Synced', const SyncedRoute()),
    ];
    expect(sushiMyVideosRailIndex(tabs), 3);
  });

  test('with no Synced tab (web, downloads off) it goes last', () {
    final tabs = [
      _tab('Dashboard', const DashboardRoute()),
      _tab('Favorites', const FavouritesRoute()),
    ];
    expect(sushiMyVideosRailIndex(tabs), 2);
  });
}
