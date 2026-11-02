import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart' as enums;
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/api_result.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/library_filters_model.dart';
import 'package:fladder/sushi/cache/sushi_catalog_providers.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_continue_store.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/sushi/sushi_local_account.dart';

part 'user_provider.g.dart';

@riverpod
bool showSyncButtonProvider(Ref ref) {
  return true;
}

@Riverpod(keepAlive: true)
class User extends _$User {
  late final JellyService api = ref.read(jellyApiProvider);

  set userState(AccountModel? account) {
    // Policy is `includeFromJson: false` — re-attach on every write so download UI stays on.
    if (account != null && sushiIsLocalAccount(account)) {
      account = sushiWithDownloadPolicy(account);
    }
    state = account?.copyWith(lastUsed: DateTime.now());
    if (account != null) {
      ref.read(sharedUtilityProvider).updateAccountInfo(account);
    }
  }

  Future<Response<bool>> quickConnect(String pin) async => api.quickConnect(pin);

  // Sushi has no HTTP backend (R-API-4) — there is no Jellyfin server to pull user
  // configuration/policy/avatar from, so this is a no-op.
  Future<Response<AccountModel>?> updateInformation() async => null;

  void setRememberAudioSelections() async {
    final newUserConfiguration = await api.updateRememberAudioSelections();
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void setRememberSubtitleSelections() async {
    final newUserConfiguration = await api.updateRememberSubtitleSelections();
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void updateSubtitleLanguagePreference(String? language) async {
    final currentUserConfiguration = state?.userConfiguration;
    if (currentUserConfiguration == null) return;

    final normalizedLanguage = language?.trim().toLowerCase();
    final updated = currentUserConfiguration.copyWithWrapped(
      subtitleLanguagePreference:
          Wrapped<String?>.value((normalizedLanguage?.isEmpty ?? true) ? null : normalizedLanguage),
    );
    final newUserConfiguration = await api.updateUserConfiguration(updated);
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void updateSubtitleMode(enums.SubtitlePlaybackMode? mode) async {
    final currentUserConfiguration = state?.userConfiguration;
    if (currentUserConfiguration == null) return;

    final updated = currentUserConfiguration.copyWith(subtitleMode: mode);
    final newUserConfiguration = await api.updateUserConfiguration(updated);
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void setBackwardSpeed(int value) {
    final userSettings = state?.userSettings?.copyWith(skipBackDuration: Duration(seconds: value));
    if (userSettings != null) {
      updateCustomConfig(userSettings);
    }
  }

  void setForwardSpeed(int value) {
    final userSettings = state?.userSettings?.copyWith(skipForwardDuration: Duration(seconds: value));
    if (userSettings != null) {
      updateCustomConfig(userSettings);
    }
  }

  Future<Response<dynamic>> updateCustomConfig(UserSettings settings) async {
    state = state?.copyWith(userSettings: settings);
    return api.setCustomConfig(settings);
  }

  Future<ApiResult> refreshMetaData(
    String itemId, {
    MetadataRefresh? metadataRefreshMode,
    bool? replaceAllMetadata,
    bool? replaceTrickplayImages,
  }) async {
    return api
        .itemsItemIdRefreshPost(
          itemId: itemId,
          metadataRefreshMode: switch (metadataRefreshMode) {
            MetadataRefresh.defaultRefresh => MetadataRefresh.defaultRefresh,
            _ => MetadataRefresh.fullRefresh,
          },
          imageRefreshMode: switch (metadataRefreshMode) {
            MetadataRefresh.defaultRefresh => MetadataRefresh.defaultRefresh,
            _ => MetadataRefresh.fullRefresh,
          },
          replaceAllMetadata: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => true,
            _ => false,
          },
          replaceAllImages: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => replaceAllMetadata,
            MetadataRefresh.validation => replaceAllMetadata,
            _ => false,
          },
          replaceTrickplayImages: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => replaceTrickplayImages,
            MetadataRefresh.validation => replaceTrickplayImages,
            _ => false,
          },
        )
        .apiResult;
  }

  Future<Response<UserData>?> setAsFavorite(bool favorite, String itemId) async {
    final response = await (favorite
        ? api.usersUserIdFavoriteItemsItemIdPost(itemId: itemId)
        : api.usersUserIdFavoriteItemsItemIdDelete(itemId: itemId));
    if (response.isSuccessful) {
      ref.read(sushiCatalogItemFlagsProvider.notifier).setFavorite(itemId, favorite);
    }
    return Response(response.base, UserData.fromDto(response.body));
  }

  /// Local flags paint immediately. Catalog episode ids also persist on
  /// `user_episode_state` (WatchedEvent) so refresh, logout, and other devices
  /// see the same mark. Skip Jellyfin — bulk season mark used to wait on 24
  /// serial POSTs that time out, so the UI never painted.
  Future<void> markManyPlayed(bool enable, List<String> itemIds) async {
    final ids = [for (final id in itemIds) if (id.isNotEmpty) id];
    if (ids.isEmpty) return;
    final flags = ref.read(sushiCatalogItemFlagsProvider.notifier);
    await flags.setPlayedMany(ids, enable);
    if (enable) {
      for (final id in ids) {
        flags.setWatchlisted(id, false);
        unawaited(sushiContinueForgetEpisode(id));
      }
    }
    final episodeIds = <int>[
      for (final id in ids)
        if (sushiEpisodeIdFromItemId(id) case final episodeId?)
          if (episodeId > 0) episodeId,
    ];
    if (episodeIds.isEmpty) return;
    final catalog = ref.read(sushiCatalogControllerProvider);
    for (final episodeId in episodeIds) {
      unawaited(catalog.markEpisodeWatchedLocally(episodeId, enable));
    }
    unawaited(sushiSendWatchedMarks([
      for (final episodeId in episodeIds) (episodeId: episodeId, done: enable),
    ]));
  }

  Future<Response<UserData>?> markAsPlayed(bool enable, String itemId) async {
    await markManyPlayed(enable, [itemId]);
    try {
      final response = await (enable
          ? api.usersUserIdPlayedItemsItemIdPost(
              itemId: itemId,
              datePlayed: DateTime.now(),
            )
          : api.usersUserIdPlayedItemsItemIdDelete(
              itemId: itemId,
            ));
      if (response.isSuccessful) {
        // Merge, do not replace — GET /me/item-flags may omit sushi_ep_* ids.
        unawaited(ref.read(sushiCatalogItemFlagsProvider.notifier).load());
      }
      return Response(response.base, UserData.fromDto(response.body));
    } catch (_) {
      return null;
    }
  }

  void clear() => userState = null;
  void updateUser(AccountModel? user) => userState = user;
  void loginUser(AccountModel? user) => state = user;
  void setAuthMethod(Authentication method) => userState = state?.copyWith(authMethod: method);
  void setLocalURL(String? value) {
    final user = state;
    if (user == null) return;
    state = user.copyWith(
      credentials: user.credentials.copyWith(localUrl: value?.isEmpty == true ? null : value),
    );
  }

  void addSearchQuery(String value) {
    if (value.isEmpty) return;
    final newList = state?.searchQueryHistory.toList() ?? [];
    if (newList.contains(value)) {
      newList.remove(value);
    }
    newList.add(value);
    userState = state?.copyWith(searchQueryHistory: newList);
  }

  void removeSearchQuery(String value) {
    userState = state?.copyWith(
      searchQueryHistory: state?.searchQueryHistory ?? []
        ..remove(value)
        ..take(50),
    );
  }

  void clearSearchQuery() {
    userState = state?.copyWith(searchQueryHistory: []);
  }

  Future<void> logoutUser() async {
    await ref.read(videoPlayerProvider).stop(leavingPlayer: true);
    if (state == null) return;
    userState = null;
  }

  Future<void> forceLogoutUser(AccountModel account) async {
    userState = account;
    try {
      await api.sessionsLogoutPost().timeout(const Duration(seconds: 8));
    } catch (_) {
      // API down / stale token — still clear the local session so splash/login can proceed.
    }
    userState = null;
  }

  @override
  AccountModel? build() {
    return null;
  }

  void removeFilter(LibraryFiltersModel model) {
    final currentList = ((state?.libraryFilters ?? [])).toList(growable: true);
    currentList.remove(model);
    userState = state?.copyWith(libraryFilters: currentList);
  }

  void saveFilter(LibraryFiltersModel model) {
    final currentList = (state?.libraryFilters ?? []).toList(growable: true);
    if (currentList.firstWhereOrNull((value) => value.id == model.id) != null) {
      userState = state?.copyWith(
          libraryFilters: currentList.map(
        (e) {
          if (e.id == model.id) {
            return model;
          } else {
            return e.copyWith(
              isFavourite: model.isFavourite && model.containsSameIds(e.ids) ? false : e.isFavourite,
            );
          }
        },
      ).toList());
    } else {
      userState = state?.copyWith(libraryFilters: [model, ...currentList]);
    }
  }

  void deleteAllFilters() => userState = state?.copyWith(libraryFilters: []);

  String? createDownloadUrl(ItemBaseModel item) =>
      Uri.encodeFull("${state?.credentials.url}/Items/${item.id}/Download?api_key=${state?.credentials.token}");

  Future<void> createNewUser(
    String userName,
    String password, {
    required bool enableAllFolders,
    required List<String> enabledFolders,
  }) async {
    final newUser = (await api.createNewUser(
      CreateUserByName(name: userName, password: password),
    ))
        .body;
    if (newUser == null) return;
    await api.setUserPolicy(
      id: newUser.id ?? "",
      policy: newUser.policy?.copyWith(
        enableAllFolders: enableAllFolders,
        enabledFolders: enabledFolders,
      ),
    );
  }
}
