import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_home_rails_provider.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_app_update.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_home_transport.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, HomeModel>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<HomeModel> {
  DashboardNotifier(this.ref) : super(HomeModel());

  final Ref ref;
  bool _sushiHomeQueued = false;
  bool _sushiHomeQueuedForce = false;
  bool _sushiHomeInFlight = false;

  Future<void> fetchNextUpAndResume({bool force = false}) async {
    // Each call is a real Telegram bot round-trip, not a cheap HTTP GET — never let two
    // overlap (e.g. pull-to-refresh landing while an initial fetch is still in flight).
    // Queue a follow-up instead of dropping: refreshOnStart often races /initbot, and dropping
    // the second call leaves rails empty until the user pulls again.
    if (_sushiHomeInFlight) {
      _sushiHomeQueued = true;
      _sushiHomeQueuedForce |= force;
      return;
    }
    _sushiHomeInFlight = true;
    try {
      var runForce = force;
      do {
        _sushiHomeQueued = false;
        final extra = _sushiHomeQueuedForce;
        _sushiHomeQueuedForce = false;
        await _fetchSushiHome(force: runForce || extra);
        runForce = false;
      } while (_sushiHomeQueued);
    } finally {
      _sushiHomeInFlight = false;
      state = state.copyWith(loading: false, loaded: true);
    }
  }

  /// Sushi: paint cache first, then `/home` only when stale or forced (docs/11 §3).
  Future<void> _fetchSushiHome({bool force = false}) async {
    final catalog = ref.read(sushiCatalogControllerProvider);
    final cached = await catalog.peekHome();
    if (cached != null && !cached.isEmpty) {
      await _applySushiHome(cached);
    }

    if (!force && cached != null && !cached.isEmpty && !await catalog.homeIsStale()) {
      debugPrint('[sushi] home cache hit seq=${cached.seq}');
      // Catalog TTL can skip rails; still ping movies `/home` so latest_app can move (ADR 0019).
      unawaited(sushiFetchHome(tab: sushiHomeTabMovies));
      return;
    }

    if (cached == null || cached.isEmpty) {
      state = state.copyWith(loading: true);
    }

    final live = await catalog.refreshHome(force: true);
    if (live == null) return;
    debugPrint(
      '[sushi] home network slider=${live.slider.length} '
      'series trending=${live.seriesTrending.length}',
    );
    await _applySushiHome(live);
  }

  Future<void> _applySushiHome(SushiCachedHome home) async {
    await sushiNoteLatestApp(home.latestApp);
    final catalog = ref.read(sushiCatalogControllerProvider);
    catalog.onTitleCached = _onSliderTitleCached;
    List<ItemBaseModel> map(List<SushiRow> rows) => rows.map(sushiRowToItemBaseModel).toList();
    Future<List<ItemBaseModel>> withHeroes(List<ItemBaseModel> items) {
      return sushiAttachCachedTitleImages(items, catalog.peekCachedTitle);
    }

    final slider = await withHeroes(map(home.slider));
    sushiApplySushiHomeRailsRef(
      ref,
      SushiHomeRailsData(
        slider: slider,
        mostWatched: map(home.mostWatched),
        trending: await withHeroes(map(home.trending)),
        seriesMostWatched: map(home.seriesMostWatched),
        seriesTrending: await withHeroes(map(home.seriesTrending)),
      ),
    );
    final resume = await withHeroes(await sushiContinueLoad());
    state = state.copyWith(nextUp: slider, resumeVideo: resume);
    unawaited(catalog.prefetchVisibleHome(home));
  }

  void _onSliderTitleCached(SushiItemRes page) {
    if (!mounted) return;
    final rails = ref.read(sushiHomeRailsProvider);
    sushiApplySushiHomeRailsRef(
      ref,
      SushiHomeRailsData(
        slider: sushiPatchHomeItemImages(rails.slider, page),
        mostWatched: rails.mostWatched,
        trending: sushiPatchHomeItemImages(rails.trending, page),
        seriesMostWatched: rails.seriesMostWatched,
        seriesTrending: sushiPatchHomeItemImages(rails.seriesTrending, page),
      ),
    );
    state = state.copyWith(
      nextUp: sushiPatchHomeItemImages(state.nextUp, page),
      resumeVideo: sushiPatchHomeItemImages(state.resumeVideo, page),
    );
  }

  /// Re-reads the client-owned continue-watching store into [state] — no `/home` bot round-trip.
  /// Driven by the poster menu's "Add / Remove Continue Watching" toggle on the home rows.
  Future<void> reloadSushiContinue() async {
    state = state.copyWith(resumeVideo: await sushiContinueLoad());
  }

  void clear() {
    state = HomeModel();
  }
}
