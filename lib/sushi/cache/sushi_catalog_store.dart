import 'package:fladder/sushi/sushi_app_update_pb.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_sync_pb.dart';

class SushiCachedHome {
  const SushiCachedHome({
    required this.slider,
    required this.mostWatched,
    required this.trending,
    required this.seriesMostWatched,
    required this.seriesTrending,
    required this.seq,
    required this.ttl,
    required this.fetchedAt,
    this.latestApp,
  });

  final List<SushiRow> slider;
  final List<SushiRow> mostWatched;
  final List<SushiRow> trending;
  final List<SushiRow> seriesMostWatched;
  final List<SushiRow> seriesTrending;
  final int seq;
  final Duration ttl;
  final DateTime fetchedAt;
  final SushiLatestApp? latestApp;

  bool get isEmpty =>
      slider.isEmpty &&
      mostWatched.isEmpty &&
      trending.isEmpty &&
      seriesMostWatched.isEmpty &&
      seriesTrending.isEmpty;
}

class SushiTitleSnapshot {
  const SushiTitleSnapshot({
    required this.page,
    required this.files,
    required this.fromCache,
    required this.lite,
    this.positionS = 0,
    this.done = false,
    this.lastFileId = 0,
    this.filesKnown = true,
  });

  final SushiItemRes? page;
  final List<SushiFile> files;
  final bool fromCache;
  final bool lite;

  /// False when a playable episode's file list never arrived. Empty [files] is then
  /// not "this title has no file" — Home rows are playable, and a timeout must not
  /// paint Request.
  final bool filesKnown;
  final int positionS;
  final bool done;
  final int lastFileId;

  SushiFilesRes get filesRes => SushiFilesRes(
        files: files,
        positionS: positionS,
        done: done,
        lastFileId: lastFileId,
        known: filesKnown,
      );
}

/// Persistence for the catalog cache. Drift is the production impl; tests use a fake.
abstract class SushiCatalogStore {
  Future<SushiItemRes?> readTitle(int tmdbId, int kind);
  Future<void> writeTitle(SushiItemRes page);
  Future<({List<SushiFile> files, DateTime fetchedAt})?> readFiles(int episodeId);
  Future<void> replaceFiles(int episodeId, List<SushiFile> files, DateTime at);
  Future<List<SushiEpisode>?> readSeason(int tmdbId, int kind, int seasonNo);
  Future<void> writeSeason(int tmdbId, int kind, int seasonNo, List<SushiEpisode> episodes);
  Future<SushiCachedHome?> readHome();
  Future<void> writeHome(SushiCachedHome home);

  /// Cross-device watched-state mirror (docs/11 §6.1). Local-first: [markEpisodeWatchedLocally]
  /// writes immediately from this device's own playback, ahead of the next [applyWatchedDelta].
  Future<bool> isEpisodeWatched(int episodeId);
  Future<int> readWatchedWatermark();
  Future<void> applyWatchedDelta(List<SushiWatchedState> rows, int watermark);
  Future<void> markEpisodeWatchedLocally(int episodeId, bool done);

  /// Drops every cached title/home/files row. Logout and session-owner mismatch call this
  /// so a previous Telegram identity cannot paint Play from leftover `/files`.
  Future<void> clearAll();
}
