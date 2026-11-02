import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/album_model.dart';
import 'package:fladder/models/items/artist_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/providers/sushi_not_interested.dart';
import 'package:fladder/sushi/sushi_playback_user_data.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/providers/dashboard_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_item_flags.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:fladder/sushi/sushi_season_availability.dart';
import 'package:fladder/sushi/sushi_season_watch_actions.dart';
import 'package:fladder/sushi/sushi_playable.dart';
import 'package:fladder/screens/metadata/identifty_screen.dart';
import 'package:fladder/screens/metadata/info_screen.dart';
import 'package:fladder/screens/playlists/add_to_playlists.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/syncing/sync_button.dart';
import 'package:fladder/screens/syncing/sync_item_details.dart';
import 'package:fladder/util/clipboard_helper.dart';
import 'package:fladder/util/file_downloader.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/pop_up/delete_file.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

extension ItemBaseModelsBooleans on List<ItemBaseModel> {
  Map<FladderItemType, List<ItemBaseModel>> get groupedItems {
    Map<FladderItemType, List<ItemBaseModel>> groupedItems = {};
    for (int i = 0; i < length; i++) {
      FladderItemType type = this[i].type;
      if (!groupedItems.containsKey(type)) {
        groupedItems[type] = [this[i]];
      } else {
        groupedItems[type]?.add(this[i]);
      }
    }
    return groupedItems;
  }

  FladderItemType get getMostCommonType {
    if (isEmpty) return FladderItemType.movie;
    final Map<FladderItemType, int> counts = {};

    for (final item in this) {
      final type = item.type;
      counts[type] = (counts[type] ?? 0) + 1;
    }

    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  double? getMostCommonAspectRatio({double tolerance = 0.01}) {
    final Map<int, List<double>> buckets = {};

    for (final item in this) {
      final aspectRatio = item.primaryRatio;
      if (aspectRatio == null) continue;

      final bucketKey = (aspectRatio / tolerance).round();

      buckets.putIfAbsent(bucketKey, () => []).add(aspectRatio);
    }

    if (buckets.isEmpty) return null;

    final mostCommonBucket = buckets.entries.reduce((a, b) => a.value.length >= b.value.length ? a : b);

    final average = mostCommonBucket.value.reduce((a, b) => a + b) / mostCommonBucket.value.length;
    return average;
  }
}

enum ItemActions {
  play,
  addToQueue,
  instantMix,
  openShow,
  openParent,
  details,
  showAlbum,
  playFromStart,
  addCollection,
  addPlaylist,
  markPlayed,
  markUnplayed,
  setFavorite,
  notInterested,
  refreshMetaData,
  editMetaData,
  mediaInfo,
  identify,
  download,
  continueWatching,
}

extension ItemBaseModelExtensions on ItemBaseModel {
  Future<void> showDetailsMenu(BuildContext context, WidgetRef ref, Offset globalPos) async {
    final position = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
    await showMenu(
      context: context,
      position: position,
      items: generateActions(
        context,
        ref,
      ).popupMenuItems(useIcons: true),
    );
  }

  List<ItemAction> generateActions(
    BuildContext context,
    WidgetRef ref, {
    List<ItemAction> otherActions = const [],
    Set<ItemActions> exclude = const {},
    bool sushiContinueToggle = false,
    Function(UserData? newData)? onUserDataChanged,
    Function(ItemBaseModel item)? onItemUpdated,
    Function(ItemBaseModel item)? onDeleteSuccesFully,
  }) {
    final isAdmin = ref.read(userProvider)?.policy?.isAdministrator ?? false;
    final hasPlaybackActions = sushiItemHasPlaybackActions(this);
    final downloadEnabled = syncAble && hasPlaybackActions;
    final downloadUrl = ref.read(userProvider.notifier).createDownloadUrl(this);
    final syncedItemFuture = ref.read(syncProvider.notifier).getSyncedItem(id);
    final showMarkAs = switch (this) {
      AlbumModel() => false,
      ArtistModel() => false,
      _ => true,
    };
    final sushiEnabled = true;
    final sushiMarkId = sushiMarkPlayedItemId(this);
    final sushiPlayed = this is SeasonModel
        ? sushiSeasonShowWatchedTick(this as SeasonModel)
        : ref.watch(sushiCatalogItemFlagsProvider.select((s) => s.isPlayed(sushiMarkId)));
    final sushiShowBothMarkActions = sushiEnabled &&
        (sushiIsActivePlaybackItem(ref, id) || (userData.progress > 0 && !userData.played));
    void applyMarkUserData(UserData? newData) {
      onUserDataChanged?.call(newData);
      if (sushiEnabled) sushiSyncPlaybackUserData(ref, id, newData);
    }
    // Sushi "Add / Remove Continue Watching" — only on the home rows that opt in (the continue
    // rail is client-owned, docs/12 §2). "In" it just means the store's entry list, which the
    // dashboard already mirrors in `resumeVideo`; compare id *and* runtime type since a movie and
    // a series can share a TMDB id and both map to `sushi_tmdb_<id>`.
    final sushiShowContinueToggle = sushiContinueToggle &&
        !exclude.contains(ItemActions.continueWatching) &&
        (this is MovieModel || this is SeriesModel);
    final sushiInContinue = sushiShowContinueToggle &&
        ref.read(dashboardProvider).resumeVideo.any((e) => e.id == id && e.runtimeType == runtimeType);
    final ItemAction? parentAction = switch (this) {
      EpisodeModel _ => !exclude.contains(ItemActions.openShow)
          ? ItemActionButton(
              icon: Icon(FladderItemType.series.icon),
              action: () => parentBaseModel.navigateTo(context),
              label: Text(context.localized.openShow),
            )
          : null,
      AudioModel _ => !exclude.contains(ItemActions.openParent)
          ? ItemActionButton(
              icon: Icon(FladderItemType.musicAlbum.icon),
              action: () => parentBaseModel.navigateTo(context),
              label: Text(context.localized.showAlbum),
            )
          : null,
      AlbumModel album => !exclude.contains(ItemActions.openParent)
          ? ItemActionButton(
              icon: Icon(FladderItemType.musicArtist.icon),
              action: () => album.parentBaseModel.navigateTo(context),
              label: Text(context.localized.showArtist),
            )
          : null,
      SeriesModel _ => null,
      _ => !exclude.contains(ItemActions.openParent) && !galleryItem
          ? ItemActionButton(
              icon: Icon(FladderItemType.folder.icon),
              action: () => parentBaseModel.navigateTo(context),
              label: Text(context.localized.openParent),
            )
          : null,
    };
    return [
      if (!exclude.contains(ItemActions.play))
        if (playAble && hasPlaybackActions)
          ItemActionButton(
            action: () => play(context, ref),
            icon: const Icon(IconsaxPlusLinear.play),
            label: Text(playButtonLabel(context.localized)),
          ),
      if (!exclude.contains(ItemActions.addToQueue))
        if (this is AudioModel || this is AlbumModel || this is ArtistModel)
          ItemActionButton(
            action: () => switch (this) {
              AudioModel audio => audio.addToQueue(context, ref),
              AlbumModel album => album.addToQueue(context, ref),
              ArtistModel artist => artist.addToQueue(context, ref),
              _ => Future.value(),
            },
            icon: const Icon(IconsaxPlusLinear.music_playlist),
            label: Text(context.localized.addToQueue),
          ),
      if (!exclude.contains(ItemActions.instantMix))
        if (this is AudioModel || this is AlbumModel || this is ArtistModel)
          ItemActionButton(
            action: () => switch (this) {
              AudioModel audio => audio.playInstantMix(context, ref),
              AlbumModel album => album.playInstantMix(context, ref),
              ArtistModel artist => artist.playInstantMix(context, ref),
              _ => Future.value(),
            },
            icon: const Icon(IconsaxPlusLinear.blend_2),
            label: Text(context.localized.instantMix),
          ),
      if (parentAction != null) parentAction,
      if (!galleryItem && !exclude.contains(ItemActions.details))
        ItemActionButton(
          action: () async => await navigateTo(context),
          icon: const Icon(IconsaxPlusLinear.main_component),
          label: Text(context.localized.showDetails),
        )
      else if (!exclude.contains(ItemActions.showAlbum) && galleryItem)
        ItemActionButton(
          icon: Icon(FladderItemType.photoAlbum.icon),
          action: () => parentBaseModel.navigateTo(context),
          label: Text(context.localized.showAlbum),
        ),
      if (!exclude.contains(ItemActions.playFromStart))
        if ((userData.progress) > 0 && hasPlaybackActions)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.refresh),
            action: (this is BookModel)
                ? () => ((this as BookModel).play(context, ref, currentPage: 0))
                : () => play(context, ref, startPosition: Duration.zero),
            label: Text((this is BookModel)
                ? context.localized.readFromStart(name)
                : context.localized.playFromStart(subTextShort(context.localized) ?? name)),
          ),
      ItemActionDivider(),
      if (!exclude.contains(ItemActions.addPlaylist))
        if (type != FladderItemType.playlist)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.archive_add),
            action: () async {
              await addItemToPlaylist(context, [this]);
              if (context.mounted) {
                context.refreshData();
              }
            },
            label: Text(context.localized.addToPlaylist),
          ),
      if (showMarkAs) ...[
        if (!exclude.contains(ItemActions.markPlayed) &&
            (!sushiEnabled || !sushiPlayed || sushiShowBothMarkActions))
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.eye),
            action: () async {
              try {
                await _sushiMarkPlayedAction(ref, this, true);
                applyMarkUserData(const UserData(played: true, progress: 0, playbackPositionTicks: 0));
              } finally {
                context.refreshData();
              }
            },
            label: Text(context.localized.markAsWatched),
          ),
        if (!exclude.contains(ItemActions.markUnplayed) &&
            (!sushiEnabled || sushiPlayed || sushiShowBothMarkActions))
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.eye_slash),
            label: Text(context.localized.markAsUnwatched),
            action: () async {
              try {
                await _sushiMarkPlayedAction(ref, this, false);
                applyMarkUserData(const UserData(played: false, progress: 0, playbackPositionTicks: 0));
              } finally {
                context.refreshData();
              }
            },
          ),
      ],
      if (!exclude.contains(ItemActions.setFavorite))
        ItemActionButton(
          icon: Icon(
            (ref.read(sushiItemFlagsProvider)[id]?.favorite ?? false)
                ? IconsaxPlusLinear.heart_remove
                : IconsaxPlusLinear.heart_add,
          ),
          action: () async {
            try {
              final on = !(ref.read(sushiItemFlagsProvider)[id]?.favorite ?? false);
              await ref.read(sushiItemFlagsProvider.notifier).setFavorite(this, on);
            } finally {
              context.refreshData();
            }
          },
          label: Text(
            (ref.read(sushiItemFlagsProvider)[id]?.favorite ?? false)
                ? context.localized.removeAsFavorite
                : context.localized.addAsFavorite,
          ),
        ),
      if (!exclude.contains(ItemActions.notInterested) && sushiContinueIdentity(this) != null)
        ItemActionButton(
          icon: Icon(
            ref.read(sushiNotInterestedProvider.notifier).isHidden(this)
                ? IconsaxPlusLinear.eye
                : IconsaxPlusLinear.eye_slash,
          ),
          label: Text(
            ref.read(sushiNotInterestedProvider.notifier).isHidden(this)
                ? 'Remove Not Interested'
                : 'Not Interested',
          ),
          action: () async {
            final hidden = ref.read(sushiNotInterestedProvider.notifier).isHidden(this);
            await ref.read(sushiNotInterestedProvider.notifier).setHidden(this, !hidden);
            if (!context.mounted) return;
            FladderSnack.show(
              hidden ? 'Removed from Not Interested' : 'Hidden from Home',
              context: context,
            );
          },
        ),
      if (sushiShowContinueToggle)
        ItemActionButton(
          icon: Icon(sushiInContinue ? IconsaxPlusLinear.play_remove : IconsaxPlusLinear.video_play),
          label: Text(sushiInContinue ? 'Remove from Continue Watching' : 'Add to Continue Watching'),
          action: () async {
            if (sushiInContinue) {
              await sushiContinueForget(this);
            } else {
              await sushiContinueAdd(this);
            }
            await ref.read(dashboardProvider.notifier).reloadSushiContinue();
            FladderSnack.show(
              sushiInContinue ? 'Removed from Continue Watching' : 'Added to Continue Watching',
              context: context,
            );
          },
        ),
      ...otherActions,
      ItemActionDivider(),
      if (!exclude.contains(ItemActions.download) && downloadEnabled) ...[
        if (!kIsWeb)
          ItemActionButton(
            icon: FutureBuilder(
              future: syncedItemFuture,
              builder: (context, snapshot) {
                final syncedItem = snapshot.data;
                if (syncedItem != null) {
                  return IgnorePointer(child: SyncButton(item: this, syncedItem: syncedItem));
                }
                return const Icon(IconsaxPlusLinear.arrow_down_2);
              },
            ),
            label: FutureBuilder(
              future: syncedItemFuture,
              builder: (context, snapshot) {
                final syncedItem = snapshot.data;
                if (syncedItem != null) {
                  return Text(
                    context.localized.syncDetails,
                  );
                }
                return Text(context.localized.sync);
              },
            ),
            action: () async {
              final syncedItem = await syncedItemFuture;
              if (syncedItem != null) {
                await showSyncItemDetails(context, syncedItem, ref);
              } else {
                await ref.read(syncProvider.notifier).addSyncItem(context, this);
              }
              context.refreshData();
            },
          )
        else if (downloadUrl != null) ...[
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.document_download),
            action: () => downloadFile(downloadUrl),
            label: Text(context.localized.downloadFile(type.label(context.localized).toLowerCase())),
          ),
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.link_21),
            action: () => context.copyToClipboard(downloadUrl),
            label: Text(context.localized.copyStreamUrl),
          )
        ],
      ],
      if (canDelete == true)
        ItemActionButton(
          icon: Container(
            child: const Icon(
              IconsaxPlusLinear.trash,
            ),
          ),
          action: () async {
            final response = await FladderSnack.showResponse(
              showDeleteDialog(context, this, ref),
              successTitle: context.localized.deletedItem(name),
            );
            if (response.isSuccess) {
              onDeleteSuccesFully?.call(this);
              if (context.mounted) {
                context.refreshData();
              }
            }
          },
          label: Text(context.localized.delete),
        ),
      if (!exclude.contains(ItemActions.identify) && identifiable && isAdmin)
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.search_normal),
          action: () async {
            showIdentifyScreen(context, this);
          },
          label: Text(context.localized.identify),
        ),
      if (!exclude.contains(ItemActions.mediaInfo))
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.info_circle),
          action: () async {
            showInfoScreen(context, this);
          },
          label: Text("${type.label(context.localized)} ${context.localized.info}"),
        ),
    ];
  }

  int? get tmdbId {
    final providerIds = this is MovieModel
        ? (this as MovieModel).providerIds
        : this is SeriesModel
            ? (this as SeriesModel).providerIds
            : null;

    if (providerIds == null || providerIds.isEmpty) return null;

    final value = providerIds['Tmdb'];
    final parsed = int.tryParse(value.toString());
    return parsed;
  }

  int? get tvdbId {
    final providerIds = this is MovieModel
        ? (this as MovieModel).providerIds
        : this is SeriesModel
            ? (this as SeriesModel).providerIds
            : null;

    if (providerIds == null || providerIds.isEmpty) return null;
    final value = providerIds['Tvdb'];
    final parsed = int.tryParse(value.toString());
    return parsed;
  }
}

Future<void> _sushiMarkPlayedAction(WidgetRef ref, ItemBaseModel item, bool played) async {
  if (item is SeasonModel) {
    await sushiSeasonMarkPlayed(ref, item, played);
    return;
  }
  await ref.read(userProvider.notifier).markAsPlayed(played, sushiMarkPlayedItemId(item));
}
