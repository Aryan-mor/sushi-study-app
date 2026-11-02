import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/syncing/download_stream.dart';
import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/sushi/cache/sushi_catalog_controller.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/sushi_bridge_queue.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_pb.dart';
import 'package:fladder/sushi/sushi_play_pb.dart';
import 'package:fladder/sushi/sushi_playback_resolver.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_sync_dto.dart';
import 'package:fladder/util/localization_helper.dart';

/// In-flight Telegram downloads, keyed by SyncedItem.id. One HTTP GET at a time — native playback
/// session is singular (TdlibBridgeObject.startPlaybackSession tears down the previous).
final Map<String, HttpClient> _sushiDownloadClients = {};
final List<String> _sushiDownloadQueue = [];
bool _sushiDownloadBusy = false;

void sushiCancelDownload(String itemId) {
  _sushiDownloadQueue.remove(itemId);
  final client = _sushiDownloadClients.remove(itemId);
  client?.close(force: true);
}

Future<void> sushiAddSyncItem(SyncNotifier sync, BuildContext context, ItemBaseModel item) async {
  debugPrint('[sushi] addSyncItem id=${item.id} type=${item.runtimeType}');
  try {
    final catalog = sync.ref.read(sushiCatalogControllerProvider);
    final created = switch (item) {
      MovieModel movie => await _syncMovie(sync, catalog, movie),
      EpisodeModel episode => await _syncEpisode(sync, catalog, episode),
      SeasonModel season => await _syncSeason(sync, catalog, season),
      SeriesModel series => await _syncSeries(sync, catalog, series),
      _ => null,
    };
    if (!context.mounted) return;
    FladderSnack.show(
      created != null
          ? context.localized.startedSyncingItem(item.detailedName(context.localized) ?? item.name)
          : context.localized.unableToSyncItem(item.detailedName(context.localized) ?? item.name),
      context: context,
    );
  } catch (e, st) {
    debugPrint('[sushi] addSyncItem failed: $e');
    log('sushi sync failed: $e\n$st');
    if (context.mounted) {
      FladderSnack.show(context.localized.somethingWentWrong, context: context);
    }
  }
}

Future<bool?> sushiSyncFile(SyncNotifier sync, SyncedItem syncItem, bool skipDownload) async {
  if (skipDownload) return true;
  if (syncItem.videoFile.existsSync()) return true;
  final fileId = sushiFileIdFromOfflineName(syncItem.videoFileName);
  if (fileId == null) {
    log('sushi syncFile: no file id on ${syncItem.id}');
    return null;
  }
  await _enqueueDownload(sync, syncItem, fileId);
  return true;
}

Future<SyncedItem?> _syncMovie(SyncNotifier sync, SushiCatalogController catalog, MovieModel movie) async {
  final tmdb = sushiTmdbIdFromItemId(movie.id);
  if (tmdb == null) return null;
  final snap = await catalog.openTitle(tmdbId: tmdb, kind: SushiKind.movie);
  if (snap.page == null) return null;
  final hydrated = sushiEnrichMovieModel(movie, snap.page!, snap.files, preferredFileId: snap.lastFileId);
  final file = sushiPickReadyFile(snap.files, versionStreamId: hydrated.streamModel?.currentVersionStream?.id);
  if (file == null) return null;
  return _createAndDownload(sync, hydrated, file);
}

Future<SyncedItem?> _syncEpisode(SyncNotifier sync, SushiCatalogController catalog, EpisodeModel episode) async {
  final series = episode.parentBaseModel;
  final tmdb = sushiTmdbIdFromItemId(series.id);
  if (tmdb == null) return null;
  final snap = await catalog.openTitle(tmdbId: tmdb, kind: SushiKind.series);
  if (snap.page == null) return null;
  final enriched = sushiEnrichSeriesModel(series, snap.page!);
  final live = enriched.availableEpisodes?.firstWhereOrNull((e) => e.id == episode.id) ?? episode;
  final episodeId = sushiEpisodeIdFromItemId(live.id);
  if (episodeId == null) return null;
  final files = await catalog.openFiles(episodeId: episodeId);
  final file = sushiPickReadyFile(files.files, versionStreamId: live.streamModel?.currentVersionStream?.id);
  if (file == null) return null;

  final seriesItem = await _upsert(sync, enriched);
  final season = enriched.seasons?.firstWhereOrNull((s) => s.season == live.season);
  final seasonItem = season == null ? null : await _upsert(sync, season, parent: seriesItem);
  return _createAndDownload(sync, live, file, parent: seasonItem ?? seriesItem);
}

Future<SyncedItem?> _syncSeason(SyncNotifier sync, SushiCatalogController catalog, SeasonModel season) async {
  final series = season.parentBaseModel;
  final tmdb = sushiTmdbIdFromItemId(series.id);
  if (tmdb == null) return null;
  final snap = await catalog.openTitle(tmdbId: tmdb, kind: SushiKind.series);
  if (snap.page == null) return null;
  final enriched = sushiEnrichSeriesModel(series, snap.page!);
  final seriesItem = await _upsert(sync, enriched);
  final liveSeason = enriched.seasons?.firstWhereOrNull((s) => s.id == season.id) ?? season;
  final seasonItem = await _upsert(sync, liveSeason, parent: seriesItem);
  SyncedItem? last;
  for (final episode in liveSeason.episodes) {
    last = await _syncEpisodeUnder(sync, catalog, episode, seriesItem: seriesItem, seasonItem: seasonItem);
  }
  return last ?? seasonItem;
}

Future<SyncedItem?> _syncSeries(SyncNotifier sync, SushiCatalogController catalog, SeriesModel series) async {
  final tmdb = sushiTmdbIdFromItemId(series.id);
  if (tmdb == null) return null;
  final snap = await catalog.openTitle(tmdbId: tmdb, kind: SushiKind.series);
  if (snap.page == null) return null;
  final enriched = sushiEnrichSeriesModel(series, snap.page!);
  final seriesItem = await _upsert(sync, enriched);
  for (final season in enriched.seasons ?? const <SeasonModel>[]) {
    final seasonItem = await _upsert(sync, season, parent: seriesItem);
    for (final episode in season.episodes) {
      await _syncEpisodeUnder(sync, catalog, episode, seriesItem: seriesItem, seasonItem: seasonItem);
    }
  }
  return seriesItem;
}

Future<SyncedItem?> _syncEpisodeUnder(
  SyncNotifier sync,
  SushiCatalogController catalog,
  EpisodeModel episode, {
  required SyncedItem seriesItem,
  required SyncedItem seasonItem,
}) async {
  final episodeId = sushiEpisodeIdFromItemId(episode.id);
  if (episodeId == null) return null;
  final files = await catalog.openFiles(episodeId: episodeId);
  final file = sushiPickReadyFile(files.files);
  if (file == null) return null;
  return _createAndDownload(sync, episode, file, parent: seasonItem);
}

Future<SyncedItem> _upsert(SyncNotifier sync, ItemBaseModel item, {SyncedItem? parent, SushiFile? file}) async {
  final existing = await sync.getSyncedItem(item.id);
  if (existing != null) return existing;
  final created = await sync.createSyncItem(sushiItemToBaseItemDto(item, file: file), parent: parent);
  final images = await sushiSaveOfflineImages(item.images, created.directory);
  final ready = images == null ? created : created.copyWith(fImages: images);
  await sync.updateItem(ready);
  return ready;
}

/// Best-effort TMDB (or any real HTTP) posters. Never throws — video download must proceed.
Future<ImagesData?> sushiSaveOfflineImages(ImagesData? data, Directory directory) async {
  if (data == null) return null;
  Future<ImageData?> one(ImageData? img, String fileName) async {
    if (img == null || !sushiImageUrlAllowed(img.path)) return img;
    try {
      final response = await http.get(Uri.parse(img.path));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return img;
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(response.bodyBytes);
      return img.copyWith(path: fileName);
    } catch (e) {
      debugPrint('[sushi] image skip $fileName: $e');
      return img;
    }
  }

  final backdrops = <ImageData>[];
  for (final backdrop in data.backDrop ?? const <ImageData>[]) {
    final saved = await one(backdrop, 'backdrop-${backdrop.key}.jpg');
    if (saved != null) backdrops.add(saved);
  }
  return ImagesData(
    primary: await one(data.primary, 'primary.jpg'),
    logo: await one(data.logo, 'logo.jpg'),
    backDrop: backdrops,
  );
}

Future<SyncedItem?> _createAndDownload(
  SyncNotifier sync,
  ItemBaseModel item,
  SushiFile file, {
  SyncedItem? parent,
}) async {
  final created = await _upsert(sync, item, parent: parent, file: file);
  await _enqueueDownload(sync, created, file.fileId);
  return created;
}

Future<void> _enqueueDownload(SyncNotifier sync, SyncedItem item, int fileId) async {
  if (item.videoFile.existsSync()) {
    debugPrint('[sushi] download skip exists item=${item.id}');
    return;
  }
  if (_sushiDownloadClients.containsKey(item.id) || _sushiDownloadQueue.contains(item.id)) {
    debugPrint('[sushi] download already queued item=${item.id}');
    return;
  }
  debugPrint('[sushi] download enqueue item=${item.id} fileId=$fileId');
  _sushiDownloadQueue.add(item.id);
  _sushiDownloadJobs[item.id] = _SushiDownloadJob(sync: sync, item: item, fileId: fileId);
  unawaited(_pumpDownloads());
}

class _SushiDownloadJob {
  _SushiDownloadJob({required this.sync, required this.item, required this.fileId});
  final SyncNotifier sync;
  final SyncedItem item;
  final int fileId;
}

final Map<String, _SushiDownloadJob> _sushiDownloadJobs = {};

Future<void> _pumpDownloads() async {
  if (_sushiDownloadBusy) return;
  _sushiDownloadBusy = true;
  try {
    while (_sushiDownloadQueue.isNotEmpty) {
      final id = _sushiDownloadQueue.removeAt(0);
      final job = _sushiDownloadJobs.remove(id);
      if (job == null) continue;
      await _runDownload(job);
    }
  } finally {
    _sushiDownloadBusy = false;
  }
}

Future<void> _runDownload(_SushiDownloadJob job) async {
  final sync = job.sync;
  final item = job.item;
  final fileId = job.fileId;
  String? sessionUri;
  HttpClient? client;
  try {
    await item.directory.create(recursive: true);
    final dummyTask = DownloadTask(
      taskId: item.id,
      url: 'http://127.0.0.1/sushi-download',
      filename: item.videoFileName ?? sushiOfflineFileName(fileId),
      directory: item.directory.path,
      baseDirectory: BaseDirectory.root,
      updates: Updates.statusAndProgress,
    );
    sync.ref.read(activeDownloadTasksProvider.notifier).update((state) {
      return [...state.where((t) => t.taskId != item.id), dummyTask];
    });
    sync.ref.read(downloadTasksProvider(item.id).notifier).update(
          (state) => DownloadStream(id: item.id, task: dummyTask, status: TaskStatus.enqueued),
        );

    debugPrint('[sushi] download start item=${item.id} fileId=$fileId');
    sessionUri = await sushiResolvePlaybackUrl(
      fileId: fileId,
      preferHttpBridge: true,
      mode: sushiModeDownload,
    );
    debugPrint('[sushi] download uri=$sessionUri');
    if (!sessionUri.startsWith('http://127.0.0.1') && !sessionUri.startsWith('http://localhost')) {
      throw StateError('sushi download needs loopback HTTP, got $sessionUri');
    }

    sync.ref.read(downloadTasksProvider(item.id).notifier).update(
          (state) => state.copyWith(status: TaskStatus.running, progress: 0),
        );

    client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(hours: 6);
    _sushiDownloadClients[item.id] = client;

    final dest = item.videoFile;
    final existing = dest.existsSync() ? dest.lengthSync() : 0;
    final request = await client.getUrl(Uri.parse(sessionUri));
    if (existing > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
    }
    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw HttpException('download HTTP ${response.statusCode}', uri: Uri.parse(sessionUri));
    }
    final total = existing + (response.contentLength > 0 ? response.contentLength : (item.fileSize ?? 0) - existing);
    var received = existing;
    final sink = dest.openWrite(mode: existing > 0 && response.statusCode == 206 ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        sync.ref.read(downloadTasksProvider(item.id).notifier).update(
              (state) => state.copyWith(status: TaskStatus.running, progress: progress),
            );
      }
    } finally {
      await sink.close();
    }

    sync.ref.read(downloadTasksProvider(item.id).notifier).update((state) => DownloadStream.empty());
    sync.ref.read(activeDownloadTasksProvider.notifier).update(
          (state) => state.where((t) => t.taskId != item.id).toList(),
        );
  } catch (e, st) {
    log('sushi download failed item=${item.id}: $e\n$st');
    sync.ref.read(downloadTasksProvider(item.id).notifier).update(
          (state) => state.copyWith(status: TaskStatus.failed),
        );
    sync.ref.read(activeDownloadTasksProvider.notifier).update(
          (state) => state.where((t) => t.taskId != item.id).toList(),
        );
  } finally {
    _sushiDownloadClients.remove(item.id);
    client?.close(force: true);
    if (sessionUri != null) {
      try {
        await sushiStopPlaybackSession(sessionUri);
      } catch (e) {
        log('sushi stopPlaybackSession after download: $e');
      }
    }
  }
}
