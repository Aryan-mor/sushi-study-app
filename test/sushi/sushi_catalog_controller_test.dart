import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/sushi_account_playback_pref.dart';
import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_play_default.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';

class _MemStore implements SushiCatalogStore {
  final Map<String, SushiItemRes> titles = {};
  final Map<String, List<SushiEpisode>> seasons = {};
  ({List<SushiFile> files, DateTime fetchedAt})? files;
  SushiCachedHome? home;
  final Map<int, bool> watched = {};
  int watchedWatermark = 0;

  String _key(int tmdbId, int kind) => '$tmdbId:$kind';

  SushiItemRes? get title => titles.isEmpty ? null : titles.values.first;

  set title(SushiItemRes? page) {
    titles.clear();
    if (page != null) {
      titles[_key(page.row.tmdbId, sushiKindToWire(page.row.kind))] = page;
    }
  }

  @override
  Future<SushiItemRes?> readTitle(int tmdbId, int kind) async => titles[_key(tmdbId, kind)];

  @override
  Future<void> writeTitle(SushiItemRes page) async {
    titles[_key(page.row.tmdbId, sushiKindToWire(page.row.kind))] = page;
  }

  @override
  Future<({List<SushiFile> files, DateTime fetchedAt})?> readFiles(int episodeId) async => files;

  @override
  Future<void> replaceFiles(int episodeId, List<SushiFile> files, DateTime at) async {
    this.files = (files: files, fetchedAt: at);
  }

  @override
  Future<List<SushiEpisode>?> readSeason(int tmdbId, int kind, int seasonNo) async =>
      seasons['$tmdbId:$kind:$seasonNo'];

  @override
  Future<void> writeSeason(int tmdbId, int kind, int seasonNo, List<SushiEpisode> episodes) async {
    seasons['$tmdbId:$kind:$seasonNo'] = episodes;
  }

  @override
  Future<SushiCachedHome?> readHome() async => home;

  @override
  Future<void> writeHome(SushiCachedHome home) async => this.home = home;

  @override
  Future<bool> isEpisodeWatched(int episodeId) async => watched[episodeId] ?? false;

  @override
  Future<int> readWatchedWatermark() async => watchedWatermark;

  @override
  Future<void> applyWatchedDelta(List<SushiWatchedState> rows, int watermark) async {
    for (final row in rows) {
      watched[row.episodeId] = row.done;
    }
    watchedWatermark = watermark;
  }

  @override
  Future<void> markEpisodeWatchedLocally(int episodeId, bool done) async {
    watched[episodeId] = done;
  }

  @override
  Future<void> clearAll() async {
    titles.clear();
    seasons.clear();
    files = null;
    home = null;
    watched.clear();
    watchedWatermark = 0;
  }
}

SushiItemRes _page({
  required int tmdbId,
  required int episodeId,
  Uint8List? wire,
  List<SushiEpisode>? episodes,
  String trailerKey = 'has-trailer',
}) {
  return SushiItemRes(
    row: SushiRow(tmdbId: tmdbId, kind: SushiKind.movie, title: 'Film', year: 2024, rating: 80, poster: 'abc'),
    overview: 'plot',
    releasedOn: 0,
    episodes: episodes ?? [SushiEpisode(episodeId: episodeId, seasonNo: 0, episodeNo: 0, title: 'Film')],
    trailerKey: trailerKey,
    wire: wire ?? Uint8List.fromList([1, 2, 3]),
  );
}

SushiFile _file(int id) => SushiFile(
      fileId: id,
      qualityLabel: '1080p',
      height: 1080,
      audioLangs: 'fa',
      subLangs: 'en',
      sizeBytes: 1,
      durationS: 100,
      state: SushiFileState.ready,
    );

SushiRow _row(int tmdbId, {SushiKind kind = SushiKind.movie}) => SushiRow(
      tmdbId: tmdbId,
      kind: kind,
      title: '$tmdbId',
      year: 2020,
      rating: 1,
      poster: '',
    );

SushiCachedHome _cachedHome({
  List<SushiRow> slider = const [],
  List<SushiRow> mostWatched = const [],
  List<SushiRow> trending = const [],
  List<SushiRow> seriesMostWatched = const [],
  List<SushiRow> seriesTrending = const [],
  int seq = 1,
}) {
  return SushiCachedHome(
    slider: slider,
    mostWatched: mostWatched,
    trending: trending,
    seriesMostWatched: seriesMostWatched,
    seriesTrending: seriesTrending,
    seq: seq,
    ttl: const Duration(hours: 1),
    fetchedAt: DateTime(2026, 1, 1),
  );
}

SushiCatalogController _catalog(
  _MemStore store, {
  SushiItemFetcher? fetchItem,
  SushiFilesFetcher? fetchFiles,
  SushiEpisodesFetcher? fetchEpisodes,
  SushiHomeFetcher? fetchHome,
  DateTime Function()? clock,
}) {
  return SushiCatalogController(
    store,
    fetchItem: fetchItem ?? ({required tmdbId, required kind}) async => null,
    fetchFiles: fetchFiles ?? ({required episodeId}) async => const SushiFilesRes(files: []),
    fetchEpisodes: fetchEpisodes ??
        ({required tmdbId, required kind, required seasonNo, int page = 0}) async =>
            const SushiEpisodesRes(episodes: []),
    fetchHome: fetchHome ?? ({required tab}) async => _homeRes(seq: 1),
    clock: clock,
    prefetchGap: Duration.zero,
    sleep: (_) async {},
  );
}

SushiHomeRes _homeRes({required int seq, List<SushiRow> slider = const []}) {
  return SushiHomeRes(
    rails: [SushiRail(kind: SushiRailKind.slider, rows: slider)],
    seq: seq,
    ttlSeconds: 3600,
  );
}

void main() {
  test('cached playable title sends files only, not item', () async {
    final store = _MemStore()
      ..title = _page(tmdbId: 10, episodeId: 99)
      ..files = (files: [_file(1)], fetchedAt: DateTime(2026, 1, 1));
    var itemCalls = 0;
    var fileCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return null;
      },
      fetchFiles: ({required episodeId}) async {
        fileCalls++;
        return SushiFilesRes(files: [_file(2)]);
      },
      clock: () => DateTime(2026, 1, 1, 0, 6), // files TTL 5 min expired
    );

    final snap = await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    expect(itemCalls, 0);
    expect(fileCalls, 1);
    expect(snap.lite, isTrue);
    expect(snap.fromCache, isTrue);
    expect(snap.files.single.fileId, 2);
  });

  test('fresh files skip network entirely', () async {
    final store = _MemStore()
      ..title = _page(tmdbId: 10, episodeId: 99)
      ..files = (files: [_file(1)], fetchedAt: DateTime(2026, 1, 1));
    var itemCalls = 0;
    var fileCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return null;
      },
      fetchFiles: ({required episodeId}) async {
        fileCalls++;
        return SushiFilesRes(files: [_file(1)]);
      },
      clock: () => DateTime(2026, 1, 1, 0, 4),
    );

    final snap = await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    expect(itemCalls, 0);
    expect(fileCalls, 0);
    expect(snap.lite, isTrue);
    expect(snap.files, isNotEmpty);
  });

  test('TMDB-only page (no episodes) is not written', () async {
    final store = _MemStore();
    final live = _page(tmdbId: 11, episodeId: 0, episodes: const []);
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async => live,
      fetchFiles: ({required episodeId}) async => const SushiFilesRes(files: []),
    );

    final snap = await catalog.openTitle(tmdbId: 11, kind: SushiKind.movie);
    expect(snap.page, isNotNull);
    expect(store.title, isNull);
  });

  test('first visit writes playable page then files', () async {
    final store = _MemStore();
    var itemCalls = 0;
    var fileCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return _page(tmdbId: tmdbId, episodeId: 7);
      },
      fetchFiles: ({required episodeId}) async {
        fileCalls++;
        return SushiFilesRes(files: [_file(1)]);
      },
    );

    final snap = await catalog.openTitle(tmdbId: 22, kind: SushiKind.movie);
    expect(itemCalls, 1);
    expect(fileCalls, 1);
    expect(snap.lite, isFalse);
    expect(store.title, isNotNull);
    expect(store.files, isNotNull);
  });

  test('cached page with no trailer key fetches item once', () async {
    final store = _MemStore()..title = _page(tmdbId: 10, episodeId: 99, trailerKey: '');
    var itemCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return _page(tmdbId: tmdbId, episodeId: 99, trailerKey: 'ytKey');
      },
      fetchFiles: ({required episodeId}) async => SushiFilesRes(files: [_file(1)]),
    );

    await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    expect(itemCalls, 1);
    expect(store.title?.trailerKey, 'ytKey');
  });

  test('empty file cache still asks the network', () async {
    final store = _MemStore();
    await store.replaceFiles(99, const [], DateTime(2026, 1, 1));
    var fileCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchFiles: ({required episodeId}) async {
        fileCalls++;
        return SushiFilesRes(files: [_file(7)]);
      },
      clock: () => DateTime(2026, 1, 1, 0, 1),
    );

    final res = await catalog.openFiles(episodeId: 99);
    expect(fileCalls, 1);
    expect(res.files.single.fileId, 7);
    expect(store.files?.files.single.fileId, 7);
  });

  test('files timeout is not an empty catalog', () async {
    final store = _MemStore()..title = _page(tmdbId: 10, episodeId: 99);
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async => null,
      fetchFiles: ({required episodeId}) async => null,
    );

    final snap = await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    expect(snap.files, isEmpty);
    expect(snap.filesKnown, isFalse);
  });

  test('server empty file list is a real miss', () async {
    final store = _MemStore()..title = _page(tmdbId: 10, episodeId: 99);
    final catalog = SushiCatalogController(
      store,
      fetchItem: ({required tmdbId, required kind}) async => null,
      fetchFiles: ({required episodeId}) async => const SushiFilesRes(files: []),
    );

    final snap = await catalog.openTitle(tmdbId: 10, kind: SushiKind.movie);
    expect(snap.files, isEmpty);
    expect(snap.filesKnown, isTrue);
  });

  test('warm home cache skips both tab fetches', () async {
    final store = _MemStore()
      ..home = SushiCachedHome(
        slider: const [
          SushiRow(tmdbId: 1, kind: SushiKind.movie, title: 'A', year: 2024, rating: 1, poster: ''),
        ],
        mostWatched: const [],
        trending: const [],
        seriesMostWatched: const [],
        seriesTrending: const [],
        seq: 9,
        ttl: const Duration(hours: 1),
        fetchedAt: DateTime(2026, 1, 1),
      );
    var homeCalls = 0;
    final catalog = SushiCatalogController(
      store,
      fetchHome: ({required tab}) async {
        homeCalls++;
        return _homeRes(seq: 10);
      },
      clock: () => DateTime(2026, 1, 1, 0, 30),
    );

    expect(await catalog.homeIsStale(), isFalse);
    await catalog.refreshHome();
    expect(homeCalls, 0);
  });

  test('stale home refetches and stores', () async {
    final store = _MemStore()
      ..home = SushiCachedHome(
        slider: const [
          SushiRow(tmdbId: 1, kind: SushiKind.movie, title: 'Old', year: 2020, rating: 1, poster: ''),
        ],
        mostWatched: const [],
        trending: const [],
        seriesMostWatched: const [],
        seriesTrending: const [],
        seq: 1,
        ttl: const Duration(hours: 1),
        fetchedAt: DateTime(2026, 1, 1),
      );
    var homeCalls = 0;
    final row = const SushiRow(tmdbId: 5, kind: SushiKind.series, title: 'S', year: 2020, rating: 1, poster: 'p');
    final catalog = SushiCatalogController(
      store,
      fetchHome: ({required tab}) async {
        homeCalls++;
        if (tab == sushiHomeTabSeries) {
          return _homeRes(seq: 11, slider: [row]);
        }
        return _homeRes(seq: 11);
      },
      clock: () => DateTime(2026, 1, 1, 2),
    );

    final live = await catalog.refreshHome();
    expect(homeCalls, 2);
    expect(live?.slider.single.tmdbId, 5);
    expect(store.home?.seq, 11);
  });

  test('stale home copies latest_app from the live movies tab', () async {
    final store = _MemStore()
      ..home = SushiCachedHome(
        slider: const [
          SushiRow(tmdbId: 1, kind: SushiKind.movie, title: 'Old', year: 2020, rating: 1, poster: ''),
        ],
        mostWatched: const [],
        trending: const [],
        seriesMostWatched: const [],
        seriesTrending: const [],
        seq: 1,
        ttl: const Duration(hours: 1),
        fetchedAt: DateTime(2026, 1, 1),
      );
    final catalog = SushiCatalogController(
      store,
      fetchHome: ({required tab}) async {
        return SushiHomeRes(
          rails: const [],
          seq: 12,
          ttlSeconds: 3600,
          latestApp: tab == sushiHomeTabMovies
              ? const SushiLatestApp(platform: 'android_new', version: '1.1.192')
              : null,
        );
      },
      clock: () => DateTime(2026, 1, 1, 2),
    );

    final live = await catalog.refreshHome();
    expect(live?.latestApp?.version, '1.1.192');
    expect(store.home?.latestApp?.platform, 'android_new');
  });

  test('home slider concat uniques overlapping TMDB ids', () async {
    final store = _MemStore();
    final catalog = SushiCatalogController(
      store,
      fetchHome: ({required tab}) async {
        if (tab == sushiHomeTabSeries) {
          return _homeRes(seq: 3, slider: [_row(2), _row(3, kind: SushiKind.series)]);
        }
        return _homeRes(seq: 3, slider: [_row(1), _row(2)]);
      },
      clock: () => DateTime(2026, 1, 1),
    );

    final live = await catalog.refreshHome();
    expect(
      live?.slider.map((r) => '${r.tmdbId}:${sushiKindToWire(r.kind)}').toList(),
      ['1:1', '2:1', '3:2'],
    );
  });

  test('prefetch plan: all slider then 2 per rail, deduped', () {
    final home = _cachedHome(
      slider: [_row(1), _row(2), _row(3), _row(4)],
      trending: [_row(4), _row(10), _row(11), _row(12)],
      seriesTrending: [_row(20, kind: SushiKind.series), _row(21, kind: SushiKind.series), _row(22, kind: SushiKind.series)],
    );
    expect(
      sushiHomePrefetchPlan(home).map((r) => r.tmdbId).toList(),
      [1, 2, 3, 4, 10, 20, 21],
    );
  });

  test('prefetch /item only, skips cached, writes playable', () async {
    final store = _MemStore()..title = _page(tmdbId: 1, episodeId: 1);
    var fileCalls = 0;
    final fetched = <int>[];
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        fetched.add(tmdbId);
        return _page(tmdbId: tmdbId, episodeId: tmdbId);
      },
      fetchFiles: ({required episodeId}) async {
        fileCalls++;
        return const SushiFilesRes(files: []);
      },
    );

    await catalog.prefetchVisibleHome(_cachedHome(slider: [_row(1), _row(2)]));
    await pumpEventQueue();

    expect(fetched, [2]);
    expect(fileCalls, 0);
    expect(store.titles.length, 2);
  });

  test('prefetch is serial and cancel drops the rest', () async {
    final store = _MemStore();
    final started = <int>[];
    final gate = Completer<void>();
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        started.add(tmdbId);
        if (tmdbId == 1) await gate.future;
        return _page(tmdbId: tmdbId, episodeId: tmdbId);
      },
    );

    await catalog.prefetchVisibleHome(_cachedHome(slider: [_row(1), _row(2), _row(3)]));
    await pumpEventQueue();
    expect(started, [1]);

    catalog.cancelPrefetch();
    gate.complete();
    await pumpEventQueue();
    expect(started, [1]);
    expect(store.titles.containsKey('1:1'), isTrue);
    expect(store.titles.containsKey('2:1'), isFalse);
  });

  test('openTitle waits for in-flight prefetch then runs as P0', () async {
    final store = _MemStore();
    final started = <int>[];
    final prefetchHold = Completer<void>();
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        started.add(tmdbId);
        if (tmdbId == 1) await prefetchHold.future;
        return _page(tmdbId: tmdbId, episodeId: tmdbId);
      },
    );

    await catalog.prefetchVisibleHome(_cachedHome(slider: [_row(1), _row(2)]));
    await pumpEventQueue();
    expect(started, [1]);

    final opened = catalog.openTitle(tmdbId: 99, kind: SushiKind.movie);
    await pumpEventQueue();
    expect(started, [1]);

    prefetchHold.complete();
    await opened;
    expect(started.first, 1);
    expect(started.contains(99), isTrue);
  });

  test('prefetch does not persist TMDB-only pages', () async {
    final store = _MemStore();
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async => _page(tmdbId: tmdbId, episodeId: 0, episodes: const []),
    );
    await catalog.prefetchVisibleHome(_cachedHome(slider: [_row(8)]));
    await pumpEventQueue();
    expect(store.titles, isEmpty);
  });

  test('prefetch persists a series with a season index', () async {
    final store = _MemStore();
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async => SushiItemRes(
        row: _row(tmdbId, kind: SushiKind.series),
        overview: '',
        releasedOn: 0,
        episodes: const [],
        seasons: const [SushiSeason(seasonNo: 1, episodeCount: 24)],
        wire: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await catalog.prefetchVisibleHome(_cachedHome(slider: [_row(8, kind: SushiKind.series)]));
    await pumpEventQueue();
    expect(store.titles, isNotEmpty);
  });

  test('openSeason fetches pages and caches the season', () async {
    final store = _MemStore();
    var calls = 0;
    final catalog = _catalog(
      store,
      fetchEpisodes: ({required tmdbId, required kind, required seasonNo, int page = 0}) async {
        calls++;
        if (page == 0) {
          return const SushiEpisodesRes(
            episodes: [SushiEpisode(episodeId: 1, seasonNo: 1, episodeNo: 1, title: 'Pilot')],
            page: 0,
            pages: 2,
          );
        }
        return const SushiEpisodesRes(
          episodes: [SushiEpisode(episodeId: 2, seasonNo: 1, episodeNo: 2, title: 'Two')],
          page: 1,
          pages: 2,
        );
      },
    );

    final first = await catalog.openSeason(tmdbId: 1396, kind: SushiKind.series, seasonNo: 1);
    expect(first, hasLength(2));
    expect(calls, 2);
    final cached = await catalog.openSeason(tmdbId: 1396, kind: SushiKind.series, seasonNo: 1);
    expect(cached, hasLength(2));
    expect(calls, 2);
  });

  test('empty session owner with stored stamp keeps catalog', () async {
    final store = _MemStore();
    store.home = _cachedHome(slider: [_row(1084244)]);
    store.files = (files: [_file(23699)], fetchedAt: DateTime(2026, 1, 1));
    var persisted = 'old-binding';
    final catalog = SushiCatalogController(
      store,
      sessionOwner: () async => '',
      readPersistedOwner: () async => persisted,
      persistOwner: (owner) async => persisted = owner,
    );
    final home = await catalog.peekHome();
    expect(home, isNotNull);
    expect(home!.slider, hasLength(1));
    expect(store.files, isNotNull);
    expect(persisted, 'old-binding');
  });

  test('empty session owner with no stamp wipes leftover home and files', () async {
    final store = _MemStore();
    store.home = _cachedHome(slider: [_row(1084244)]);
    store.files = (files: [_file(23699)], fetchedAt: DateTime(2026, 1, 1));
    var persisted = '';
    final catalog = SushiCatalogController(
      store,
      sessionOwner: () async => '',
      readPersistedOwner: () async => persisted,
      persistOwner: (owner) async => persisted = owner,
    );
    expect(await catalog.peekHome(), isNull);
    expect(store.home, isNull);
    expect(store.files, isNull);
  });

  test('same session owner keeps cached home', () async {
    final store = _MemStore();
    store.home = _cachedHome(slider: [_row(1)]);
    var persisted = 'token-a';
    final catalog = SushiCatalogController(
      store,
      sessionOwner: () async => 'token-a',
      readPersistedOwner: () async => persisted,
      persistOwner: (owner) async => persisted = owner,
    );
    final home = await catalog.peekHome();
    expect(home, isNotNull);
    expect(home!.slider, hasLength(1));
    expect(store.home, isNotNull);
  });

  test('session owner change wipes catalog', () async {
    final store = _MemStore();
    store.home = _cachedHome(slider: [_row(1)]);
    var persisted = 'token-a';
    final catalog = SushiCatalogController(
      store,
      sessionOwner: () async => 'token-b',
      readPersistedOwner: () async => persisted,
      persistOwner: (owner) async => persisted = owner,
    );
    expect(await catalog.peekHome(), isNull);
    expect(store.home, isNull);
    expect(persisted, 'token-b');
  });

  // Cross-device watched-state sync (docs/11 §6.1).
  test('refreshWatchedState applies the delta and advances the watermark', () async {
    final store = _MemStore();
    final catalog = SushiCatalogController(
      store,
      fetchSync: ({required watchedWatermark}) async {
        expect(watchedWatermark, 0);
        return const SushiSyncRes(
          watched: [SushiWatchedState(episodeId: 1, done: true)],
          watchedWatermark: 30,
          watchedMore: false,
        );
      },
    );

    await catalog.refreshWatchedState();
    expect(store.watched[1], true);
    expect(store.watchedWatermark, 30);
    expect(await catalog.isEpisodeWatched(1), true);
  });

  test('refreshWatchedState loops while watched_more is true, passing each new watermark', () async {
    final store = _MemStore();
    final calls = <int>[];
    final catalog = SushiCatalogController(
      store,
      fetchSync: ({required watchedWatermark}) async {
        calls.add(watchedWatermark);
        if (watchedWatermark == 0) {
          return const SushiSyncRes(
            watched: [SushiWatchedState(episodeId: 1, done: true)],
            watchedWatermark: 10,
            watchedMore: true,
          );
        }
        return const SushiSyncRes(
          watched: [SushiWatchedState(episodeId: 2, done: true)],
          watchedWatermark: 20,
          watchedMore: false,
        );
      },
    );

    await catalog.refreshWatchedState();
    expect(calls, [0, 10]);
    expect(store.watched, {1: true, 2: true});
    expect(store.watchedWatermark, 20);
  });

  test('refreshWatchedState stores the account playback answer; logout clears it', () async {
    final saved = <SushiAccountPlaybackPref>[];
    final catalog = SushiCatalogController(
      _MemStore(),
      fetchSync: ({required watchedWatermark}) async => const SushiSyncRes(
        watched: [],
        watchedWatermark: 0,
        watchedMore: false,
        audioPref: 'original',
        maxHeight: 720,
      ),
      savePlaybackPref: (pref) async => saved.add(pref),
    );

    await catalog.refreshWatchedState();
    expect(saved, [const SushiAccountPlaybackPref(audio: SushiAudioPref.original, maxHeight: 720)]);
    await catalog.wipeSession();
    expect(saved.last.isUnset, isTrue);
  });

  test('refreshWatchedState leaves the store untouched when the fetch fails', () async {
    final store = _MemStore()..watchedWatermark = 5;
    final catalog = SushiCatalogController(
      store,
      fetchSync: ({required watchedWatermark}) async => null,
    );

    await catalog.refreshWatchedState();
    expect(store.watched, isEmpty);
    expect(store.watchedWatermark, 5);
  });

  test('revalidateSeriesStructure joins an in-flight refresh', () async {
    final store = _MemStore();
    final gate = Completer<void>();
    var itemCalls = 0;
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        await gate.future;
        return SushiItemRes(
          row: SushiRow(tmdbId: tmdbId, kind: SushiKind.series, title: 'Show', year: 2026, rating: 1, poster: ''),
          overview: '',
          releasedOn: 0,
          episodes: const [SushiEpisode(episodeId: 1, seasonNo: 1, episodeNo: 1, title: 'One')],
          seasons: const [SushiSeason(seasonNo: 1, episodeCount: 1)],
          wire: Uint8List.fromList([1]),
        );
      },
    );

    final first = catalog.revalidateSeriesStructure(tmdbId: 9);
    var spins = 0;
    while (itemCalls == 0 && spins < 20) {
      spins++;
      await Future<void>.delayed(Duration.zero);
    }
    expect(itemCalls, 1);
    final second = catalog.revalidateSeriesStructure(tmdbId: 9);
    await Future<void>.delayed(Duration.zero);
    expect(itemCalls, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(itemCalls, 1);
  });

  test('revalidateSeriesStructure replaces a same-length season list', () async {
    final store = _MemStore();
    const stale = [
      SushiEpisode(episodeId: 3523, seasonNo: 1, episodeNo: 14, title: 'Fourteen'),
    ];
    const liveEpisodes = [
      SushiEpisode(episodeId: 77059, seasonNo: 1, episodeNo: 15, title: 'Fifteen'),
    ];
    await store.writeSeason(322499, sushiKindToWire(SushiKind.series), 1, stale);
    var itemCalls = 0;
    var episodeCalls = 0;
    var now = DateTime(2026, 9, 27);
    final catalog = _catalog(
      store,
      clock: () => now,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return SushiItemRes(
          row: SushiRow(
            tmdbId: tmdbId,
            kind: SushiKind.series,
            title: 'Possible Love',
            year: 2026,
            rating: 1,
            poster: '',
          ),
          overview: '',
          releasedOn: 0,
          episodes: const [SushiEpisode(episodeId: 3523, seasonNo: 1, episodeNo: 1, title: 'One')],
          seasons: const [SushiSeason(seasonNo: 1, episodeCount: 1)],
          wire: Uint8List.fromList([1]),
        );
      },
      fetchEpisodes: ({required tmdbId, required kind, required seasonNo, int page = 0}) async {
        episodeCalls++;
        return const SushiEpisodesRes(episodes: liveEpisodes, page: 0, pages: 1);
      },
    );

    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(itemCalls, 1);
    expect(episodeCalls, 1);
    expect((await store.readSeason(322499, sushiKindToWire(SushiKind.series), 1))!.single.episodeId, 77059);

    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(itemCalls, 1);
    expect(episodeCalls, 1);

    catalog.noteCatalogTouched(322499);
    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(itemCalls, 2);

    now = now.add(sushiSeriesStructureTtl);
    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(itemCalls, 3);
  });

  test('revalidateSeriesStructure does not prefetch a season that was never opened', () async {
    final store = _MemStore();
    var episodeCalls = 0;
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async => SushiItemRes(
        row: SushiRow(tmdbId: tmdbId, kind: SushiKind.series, title: 'Show', year: 2026, rating: 1, poster: ''),
        overview: '',
        releasedOn: 0,
        episodes: const [SushiEpisode(episodeId: 1, seasonNo: 1, episodeNo: 1, title: 'One')],
        seasons: const [SushiSeason(seasonNo: 1, episodeCount: 15)],
        wire: Uint8List.fromList([1]),
      ),
      fetchEpisodes: ({required tmdbId, required kind, required seasonNo, int page = 0}) async {
        episodeCalls++;
        return const SushiEpisodesRes(episodes: [], page: 0, pages: 1);
      },
    );

    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(episodeCalls, 0);
  });

  test('revalidateSeriesStructure retries when /item fails', () async {
    final store = _MemStore();
    var itemCalls = 0;
    final catalog = _catalog(
      store,
      fetchItem: ({required tmdbId, required kind}) async {
        itemCalls++;
        return null;
      },
    );

    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    await catalog.revalidateSeriesStructure(tmdbId: 322499);
    expect(itemCalls, 2);
  });

  test('sushiResolveStubEpisode force-refreshes a stale season and ignores a sibling file', () async {
    final store = _MemStore();
    await store.writeSeason(322499, sushiKindToWire(SushiKind.series), 1, const [
      SushiEpisode(episodeId: 3523, seasonNo: 1, episodeNo: 1, title: 'One'),
    ]);
    var episodeCalls = 0;
    final catalog = _catalog(
      store,
      fetchEpisodes: ({required tmdbId, required kind, required seasonNo, int page = 0}) async {
        episodeCalls++;
        return const SushiEpisodesRes(
          episodes: [SushiEpisode(episodeId: 77059, seasonNo: 1, episodeNo: 15, title: 'Fifteen')],
          page: 0,
          pages: 1,
        );
      },
    );
    final stub = EpisodeModel(
      seriesName: 'Possible Love',
      season: 1,
      episode: 15,
      episodeEnd: null,
      location: ItemLocation.filesystem,
      name: 'Episode 15',
      id: 'sushi_ep_stub_sushi_tmdb_322499_1_15',
      overview: const OverviewModel(),
      parentId: 'sushi_tmdb_322499',
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
    );

    final resolved = await sushiResolveStubEpisode(stub, catalog);
    expect(episodeCalls, 1);
    expect(resolved?.id, sushiEpisodeItemId(77059));
    expect(resolved?.mediaStreams.versionStreams, isEmpty);
  });
}
