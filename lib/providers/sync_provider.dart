import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:background_downloader/background_downloader.dart';
import 'package:collection/collection.dart';
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/syncing/database_item.dart';
import 'package:fladder/models/syncing/download_stream.dart';
import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/models/syncing/sync_settings_model.dart';
import 'package:fladder/models/syncing/transcode_download_model.dart';
import 'package:fladder/models/syncing/transcode_music_download_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/sync/background_download_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/sushi/sushi_sync.dart';
import 'package:fladder/util/duration_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';

final syncProvider = StateNotifierProvider<SyncNotifier, SyncSettingsModel>((ref) => throw UnimplementedError());

final downloadTasksProvider = StateProvider.family<DownloadStream, String?>((ref, id) => DownloadStream.empty());

final activeDownloadTasksProvider = StateProvider<List<DownloadTask>>((ref) {
  return [];
});

const syncPathKey = "syncPathKey";

class SyncNotifier extends StateNotifier<SyncSettingsModel> {
  SyncNotifier(this.ref, this.mobileDirectory) : super(SyncSettingsModel()) {
    _init();
  }

  final Ref ref;
  late AppDatabase _db = AppDatabase(ref);
  final Directory mobileDirectory;
  final String subPath = "Synced";

  bool updatingSyncStatus = false;

  StreamSubscription<List<SyncedItem>>? _subscription;

  @override
  set state(SyncSettingsModel value) {
    super.state = value;
    updateSyncStates();
  }

  // Sushi has no HTTP backend (R-API-4) — items never carry unSyncedData that needs pushing back
  // to a Jellyfin server, so this is a no-op.
  Future<void> updateSyncStates() async {}

  void _init() {
    cleanupTemporaryFiles();
    ref.listen(
      userProvider,
      (previous, next) {
        if (previous?.id != next?.id) {
          if (next?.id != null) {
            _initializeQueryStream(id: next!.id);
          }
        }
      },
    );

    ref.listen(connectivityStatusProvider, (_, next) {
      if (next != ConnectionState.offline) {
        updateSyncStates();
      }
    });
    _initializeQueryStream();
  }

  void _initializeQueryStream({String? id}) async {
    final userId = id ?? ref.read(userProvider)?.id;
    _subscription?.cancel();
    state = state.copyWith(items: []);

    if (userId == null) return;

    final queryStream = _db.getAllItems.watch().map(_rootSyncItems);
    final initItems = _rootSyncItems(await _db.getAllItems.get());

    state = state.copyWith(items: initItems);

    _subscription = queryStream.listen((items) {
      state = state.copyWith(items: items);
    });
  }

  List<SyncedItem> _rootSyncItems(List<SyncedItem> items) {
    return items.where((item) => item.parentId == null).toList();
  }

  Future<void> cleanupTemporaryFiles() async {
    final activeDownloads = ref.read(activeDownloadTasksProvider);
    if (activeDownloads.isNotEmpty) return;

    // List of directories to check
    final directories = [
      //Desktop directory
      await getTemporaryDirectory(),
      //Mobile directory
      await getApplicationSupportDirectory(),
    ];

    for (final dir in directories) {
      final List<FileSystemEntity> files = dir.listSync();

      for (var file in files) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          try {
            final fileSize = await file.length();
            if (fileName.startsWith('com.bbflight.background_downloader') && fileSize != 0) {
              try {
                await file.delete();
                log('Deleted temporary file: $fileName from ${dir.path}');
              } catch (e) {
                log('Failed to delete file $fileName: $e');
              }
            }
          } on PathAccessException {
            // Skip files that are inaccessible
            continue;
          }
        }
      }
    }
  }

  Future<List<String>> getTempFiles() async {
    final tempFiles = <String>[];

    // List of directories to check
    final directories = [
      //Desktop directory
      await getTemporaryDirectory(),
      //Mobile directory
      await getApplicationSupportDirectory(),
    ];

    for (final dir in directories) {
      final List<FileSystemEntity> files = dir.listSync();

      for (var file in files) {
        if (file is File) {
          final fileName = file.path.split(Platform.pathSeparator).last;
          final fileSize = await file.length();
          if (fileName.startsWith('com.bbflight.background_downloader') && fileSize != 0) {
            tempFiles.add(file.path);
          }
        }
      }
    }

    return tempFiles;
  }

  late final JellyService api = ref.read(jellyApiProvider);

  String? get _savePath => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      ? ref.read(clientSettingsProvider.select((value) => value.syncPath))
      : mobileDirectory.path;

  String? get savePath => _savePath;

  Directory get mainDirectory => Directory(path.joinAll([_savePath ?? "", subPath]));

  Directory? get saveDirectory {
    if (kIsWeb) return null;
    final directory = _savePath != null
        ? Directory(path.joinAll([_savePath ?? "", subPath, ref.read(userProvider)?.id ?? "UnknownUser"]))
        : null;
    directory?.createSync(recursive: true);
    if (directory?.existsSync() == true) {
      final noMedia = File(path.joinAll([directory?.path ?? "", ".nomedia"]));
      noMedia.writeAsString('');
    }
    return directory;
  }

  String? get syncPath => saveDirectory?.path;

  Future<int> get directorySize async {
    if (saveDirectory == null) return 0;
    var files = await saveDirectory!.list(recursive: true).toList();
    var dirSize = files.fold(0, (int sum, file) => sum + file.statSync().size);
    return dirSize;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> refresh() async => state = state.copyWith(items: _rootSyncItems(await _db.getAllItems.get()));

  Future<List<SyncedItem>> getNestedChildren(SyncedItem item) async {
    if (item.itemModel?.type == FladderItemType.playlist) {
      return _getPlaylistChildrenFromOverlay(item);
    }
    return _db.getNestedChildren(item);
  }

  Future<List<SyncedItem>> getChildren(String parentId) async => await _db.getChildren(parentId).get();

  Future<List<SyncedItem>> getChildrenForItem(SyncedItem item) async {
    if (item.itemModel?.type == FladderItemType.playlist) {
      return _getPlaylistChildrenFromOverlay(item);
    }
    return getChildren(item.id);
  }

  Future<List<SyncedItem>> _getPlaylistChildrenFromOverlay(SyncedItem item) async {
    final childIds = item.playlistChildIds;
    if (childIds.isEmpty) return [];

    final children = await Future.wait(childIds.map(getSyncedItem));
    return children.whereType<SyncedItem>().where((child) => child.itemModel is AudioModel).toList();
  }

  Future<List<SyncedItem>> getSiblings(SyncedItem syncedItem) async {
    if (syncedItem.parentId == null) return [];
    return getChildren(syncedItem.parentId!);
  }

  Future<SyncedItem?> getSyncedItem(String? id) async {
    if (id == null) return null;
    return await _db.getItem(id).getSingleOrNull();
  }

  Stream<SyncedItem?> watchItem(String id) => _db.getItem(id).watchSingleOrNull();

  Future<SyncedItem?> getParentItem(String id) async => await _db.getParent(id).getSingleOrNull();

  // Sushi has no HTTP backend (R-API-4) — synced items have no server to re-fetch metadata
  // from, so pull-to-refresh on a synced item's detail page is a no-op.
  Future<SyncedItem> refreshSyncItem(SyncedItem item) async => item;

  Future<void> addSyncItem(BuildContext? context, ItemBaseModel item) async {
    try {
      if (context == null) return;

      if (saveDirectory == null) {
        String? selectedDirectory =
            await FilePicker.platform.getDirectoryPath(dialogTitle: context.localized.syncSelectDownloadsFolder);
        if (selectedDirectory?.isEmpty == context.mounted) {
          FladderSnack.show(context.localized.syncNoFolderSetup, context: context);
          return;
        }
        ref.read(clientSettingsProvider.notifier).setSyncPath(selectedDirectory);
      }

      FladderSnack.show(context.localized.syncAddItemForSyncing(item.detailedName(context.localized) ?? "Unknown"),
          context: context);
      await sushiAddSyncItem(this, context, item);
    } catch (e) {
      log('Error adding sync item: ${e.toString()}');
      if (context?.mounted == true) {
        FladderSnack.show(context!.localized.somethingWentWrong, context: context);
      }
    }
  }

  void viewDatabase(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (context) => DriftDbViewer(_db)));

  Future<bool> removeSync(BuildContext context, SyncedItem? item) async {
    try {
      if (item == null) return false;

      final nestedChildren = await getNestedChildren(item);

      state = state.copyWith(
          items: state.items
              .map(
                (e) => e.copyWith(markedForDelete: e.id == item.id ? true : false),
              )
              .toList());

      await ref.read(backgroundDownloaderProvider).cancelTaskWithId(item.id);

      
        sushiCancelDownload(item.id);
        for (final element in nestedChildren) {
          sushiCancelDownload(element.id);
        }
      

      await _db.deleteAllItems([...nestedChildren, item]);

      for (var i = 0; i < nestedChildren.length; i++) {
        final element = nestedChildren[i];
        await ref.read(backgroundDownloaderProvider).cancelTaskWithId(element.id);
        if (await element.directory.exists()) {
          await element.directory.delete(recursive: true);
        }
      }

      if (await item.directory.exists()) {
        await item.directory.delete(recursive: true);
      }

      return true;
    } catch (e) {
      log('Error deleting synced item ${e.toString()}');
      state = state.copyWith(items: state.items.map((e) => e.copyWith(markedForDelete: false)).toList());
      FladderSnack.show(context.localized.syncRemoveUnableToDeleteItem, context: context);
      return false;
    }
  }

  Future<bool> removePlaylistSync(
    BuildContext context,
    SyncedItem item, {
    required bool removeLinkedItems,
  }) async {
    try {
      state = state.copyWith(
          items: state.items.map((e) => e.copyWith(markedForDelete: e.id == item.id ? true : false)).toList());

      await ref.read(backgroundDownloaderProvider).cancelTaskWithId(item.id);

      if (removeLinkedItems) {
        final linkedIds = item.playlistChildIds;
        final removedTracks = <SyncedItem>[];
        for (final id in linkedIds) {
          final linkedItem = await getSyncedItem(id);
          if (linkedItem == null) continue;
          if (linkedItem.itemModel is AudioModel) {
            removedTracks.add(linkedItem);
          }
          await _deleteSyncedItemAndFiles(linkedItem);
        }

        await _cleanupOrphanedMusicParents(removedTracks);
      }

      await _deleteSyncedItemAndFiles(item);

      return true;
    } catch (e) {
      log('Error deleting synced playlist ${e.toString()}');
      state = state.copyWith(items: state.items.map((e) => e.copyWith(markedForDelete: false)).toList());
      FladderSnack.show(context.localized.syncRemoveUnableToDeleteItem, context: context);
      return false;
    }
  }

  Future<void> _deleteSyncedItemAndFiles(SyncedItem item) async {
    
      sushiCancelDownload(item.id);
    
    await ref.read(backgroundDownloaderProvider).cancelTaskWithId(item.id);
    await _db.deleteAllItems([item]);
    if (await item.directory.exists()) {
      await item.directory.delete(recursive: true);
    }
  }

  Future<bool> _hasSyncedAudioDescendants(String parentId) async {
    final queue = <SyncedItem>[...await getChildren(parentId)];

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (current.itemModel is AudioModel) return true;
      queue.addAll(await getChildren(current.id));
    }

    return false;
  }

  Future<void> _cleanupOrphanedMusicParents(Iterable<SyncedItem> removedTracks) async {
    final candidateAlbumIds = <String>{};
    final candidateArtistIds = <String>{};

    for (final removedTrack in removedTracks) {
      final parentId = removedTrack.parentId;
      if (parentId == null) continue;

      final parent = await getSyncedItem(parentId);
      if (parent == null) continue;

      switch (parent.itemModel?.type) {
        case FladderItemType.musicAlbum:
          candidateAlbumIds.add(parent.id);
          if (parent.parentId != null) {
            candidateArtistIds.add(parent.parentId!);
          }
          break;
        case FladderItemType.musicArtist:
          candidateArtistIds.add(parent.id);
          break;
        default:
          break;
      }
    }

    for (final albumId in candidateAlbumIds) {
      final album = await getSyncedItem(albumId);
      if (album == null || album.itemModel?.type != FladderItemType.musicAlbum) continue;

      final hasTracks = await _hasSyncedAudioDescendants(album.id);
      if (hasTracks) continue;

      if (album.parentId != null) {
        candidateArtistIds.add(album.parentId!);
      }

      await _deleteSyncedItemAndFiles(album);
    }

    for (final artistId in candidateArtistIds) {
      final artist = await getSyncedItem(artistId);
      if (artist == null || artist.itemModel?.type != FladderItemType.musicArtist) continue;

      final hasTracks = await _hasSyncedAudioDescendants(artist.id);
      if (hasTracks) continue;

      await _deleteSyncedItemAndFiles(artist);
    }
  }

  Future<int> updateItem(SyncedItem item) async {
    return _db.insertItem(item);
  }

  Future<SyncedItem> deleteFullSyncFiles(SyncedItem syncedItem, DownloadTask? task) async {
    
      sushiCancelDownload(syncedItem.id);
    
    await syncedItem.deleteDatFiles(ref);

    syncedItem = syncedItem.copyWith(
      transcodeDownloadModel: null,
    );
    await updateItem(syncedItem);

    ref.read(downloadTasksProvider(syncedItem.id).notifier).update((state) => DownloadStream.empty());

    ref.read(backgroundDownloaderProvider).cancelTaskWithId(syncedItem.id);

    cleanupTemporaryFiles();
    refresh();
    return syncedItem;
  }

  Future<bool?> syncFile(
    SyncedItem syncItem,
    bool skipDownload, {
    TranscodeDownloadModel? transcodeModel,
    TranscodeMusicDownloadModel? musicTranscodeModel,
  }) async {
    cleanupTemporaryFiles();
    return sushiSyncFile(this, syncItem, skipDownload);
  }

  Future<void> removeAllSyncedData() async {
    if (await mainDirectory.exists()) {
      await mainDirectory.delete(recursive: true);
    }
    await _db.close();
    await _db.clearDatabase();
    _db = AppDatabase(ref);
    state = state.copyWith(items: []);
  }

  Future<void> updatePlaybackPosition({String? itemId, required Duration position}) async {
    if (itemId == null) return;

    final syncedItem = await _db.getItem(itemId).getSingleOrNull();
    if (syncedItem == null) return;

    final item = syncedItem.itemModel;
    if (item == null) return;

    final progress = position.inMilliseconds / (item.overview.runTime?.inMilliseconds ?? 0) * 100;

    final updatedItem = syncedItem.copyWith(
      userData: syncedItem.userData?.copyWith(
        playbackPositionTicks: position.toRuntimeTicks,
        progress: progress,
        played: UserData.isPlayed(position, item.overview.runTime ?? Duration.zero),
      ),
    );
    await _db.insertItem(updatedItem);
  }

  Future<void> updatePlayedItem(String? itemId,
      {DateTime? datePlayed, required bool played, bool responseSuccessful = false}) async {
    if (itemId == null) return;

    final syncedItem = _db.getItem(itemId).getSingleOrNull();
    syncedItem.then((item) async {
      if (item == null) return;
      final updatedUserData = item.userData?.copyWith(
        played: played,
        playbackPositionTicks: 0,
        progress: 0.0,
        lastPlayed: datePlayed ?? DateTime.now().toUtc(),
      );
      SyncedItem updatedItem = item.copyWith(userData: updatedUserData, unSyncedData: !responseSuccessful);

      List<SyncedItem> children = [];
      final shouldUpdateChildren = {FladderItemType.series, FladderItemType.season}.contains(item.itemModel?.type);
      if (shouldUpdateChildren) {
        // Update child items with the same played status, jellyfin server does this was well
        // when marking a series or season as played
        children = (await getNestedChildren(item))
            .map((e) => e.copyWith(
                  userData: e.userData?.copyWith(
                    played: played,
                    playbackPositionTicks: 0,
                    progress: 0.0,
                  ),
                ))
            .toList();
      }
      await _db.insertMultipleEntries([updatedItem, ...children]);
    });
  }

  Future<void> updateFavoriteItem(String? itemId, {required bool isFavorite, bool responseSuccessful = false}) async {
    if (itemId == null) return;

    final syncedItem = _db.getItem(itemId).getSingleOrNull();
    syncedItem.then((item) async {
      if (item == null) return;
      final updatedUserData = item.userData?.copyWith(isFavourite: isFavorite);
      final updatedItem = item.copyWith(userData: updatedUserData, unSyncedData: !responseSuccessful);
      await _db.insertItem(updatedItem);
    });
  }
}

extension SyncNotifierHelpers on SyncNotifier {
  Future<SyncedItem> createSyncItem(BaseItemDto response, {SyncedItem? parent}) async {
    final ItemBaseModel item = ItemBaseModel.fromBaseDto(response, ref);

    final existingSyncedItem = await getSyncedItem(item.id);

    if (existingSyncedItem != null) return existingSyncedItem;

    SyncedItem syncItem = await _syncItemData(parent, item, response);

    if (parent == null) {
      await _db.insertItem(syncItem);
    }

    return syncItem.copyWith(
      fileSize: response.mediaSources?.firstOrNull?.size ?? 0,
      syncing: false,
      videoFileName: response.path?.universalBasename ?? "",
    );
  }

  Future<SyncedItem> _syncItemData(SyncedItem? parent, ItemBaseModel item, BaseItemDto response) async {
    final Directory? parentDirectory = parent?.directory;

    final directory = Directory(path.joinAll([(parentDirectory ?? saveDirectory)?.path ?? "", item.id]));

    await directory.create(recursive: true);

    File dataFile = File(path.joinAll([directory.path, 'data.json']));
    await dataFile.writeAsString(jsonEncode(response.toJson()));
    // Sushi has no Jellyfin image host (`sushi://local` → DNS fail on `http://sushi/...`).
    // TMDB posters are saved in sushi_sync `_upsert` from the live ItemBaseModel.
    final imageData = item is AudioModel
        ? _audioImageDataFromParent(parent: parent, directory: directory)
        : null;

    SyncedItem syncItem = SyncedItem(
      syncing: true,
      id: item.id,
      parentId: parent?.id,
      sortName: response.sortName,
      fImages: imageData,
      userId: ref.read(userProvider)?.id ?? "",
      path: directory.path,
      userData: item.userData,
    );
    return syncItem;
  }

  ImagesData? _audioImageDataFromParent({required SyncedItem? parent, required Directory directory}) {
    final parentImages = parent?.fImages;
    final parentDirectory = parent?.directory;

    if (parentImages == null || parentDirectory == null) return null;

    ImageData? rebasePath(ImageData? image) {
      final imagePath = image?.path;
      if (imagePath == null || imagePath.isEmpty) return null;

      final absoluteParentPath = path.join(parentDirectory.path, imagePath);
      final relativePath = path.relative(absoluteParentPath, from: directory.path);

      return image?.copyWith(path: relativePath);
    }

    return parentImages.copyWith(
      primary: () => rebasePath(parentImages.primary),
      logo: () => rebasePath(parentImages.logo),
      backDrop: () => (parentImages.backDrop ?? []).map((image) => rebasePath(image)).whereType<ImageData>().toList(),
    );
  }

}
