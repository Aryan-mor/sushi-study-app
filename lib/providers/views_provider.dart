import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/views_model.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/sushi/sushi_views.dart';

final viewsProvider = StateNotifierProvider<ViewsNotifier, ViewsModel>((ref) {
  return ViewsNotifier(ref);
});

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel());

  final Ref ref;

  bool _fetchInFlight = false;

  Future<ViewsModel?> fetchViews({bool background = false}) async {
    Future<ViewsModel?> load() async {
      if (_fetchInFlight) return null;
      _fetchInFlight = true;
      try {
        // Sushi: synthetic library views (Movies/Series/Box sets/Playlists) + empty home rails.
        final sushiViews = sushiSyntheticViews();
        state = state.copyWith(
          views: sushiViews,
          dashboardViews: const [],
          loading: false,
          loaded: true,
        );
        return state;
      } finally {
        _fetchInFlight = false;
      }
    }

    return SushiScreenTelemetry.trackLoad(screen: 'home', phase: 'views', load: load);
  }

  void clear() {
    state = ViewsModel();
  }
}
