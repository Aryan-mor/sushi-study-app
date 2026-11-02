import 'package:flutter/material.dart';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/recommended_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/sushi/sushi_screen_telemetry.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/localization_helper.dart';

part 'library_screen_provider.freezed.dart';
part 'library_screen_provider.g.dart';

Set<LibraryViewType> libraryLoadTypes(LibraryScreenModel state) {
  if (state.viewType.isEmpty) {
    return {LibraryViewType.recommended};
  }
  return state.viewType;
}

enum LibraryViewType {
  recommended,
  favourites,
  genres;

  const LibraryViewType();

  String label(BuildContext context) => switch (this) {
        LibraryViewType.recommended => context.localized.recommended,
        LibraryViewType.favourites => context.localized.favorites,
        LibraryViewType.genres => context.localized.genre(2),
      };

  IconData get icon => switch (this) {
        LibraryViewType.recommended => IconsaxPlusLinear.star,
        LibraryViewType.favourites => IconsaxPlusLinear.heart,
        LibraryViewType.genres => IconsaxPlusLinear.hierarchy_3,
      };

  IconData get iconSelected => switch (this) {
        LibraryViewType.recommended => IconsaxPlusBold.star,
        LibraryViewType.favourites => IconsaxPlusBold.heart,
        LibraryViewType.genres => IconsaxPlusBold.hierarchy_3,
      };
}

@Freezed(fromJson: false, toJson: false, copyWith: true)
abstract class LibraryScreenModel with _$LibraryScreenModel {
  factory LibraryScreenModel({
    @Default([]) List<ViewModel> views,
    ViewModel? selectedViewModel,
    @Default({LibraryViewType.recommended, LibraryViewType.favourites}) Set<LibraryViewType> viewType,
    @Default([]) List<RecommendedModel> recommendations,
    @Default([]) List<RecommendedModel> genres,
    @Default([]) List<ItemBaseModel> favourites,
  }) = _LibraryScreenModel;
}

@Riverpod(keepAlive: true)
class LibraryScreen extends _$LibraryScreen {
  @override
  LibraryScreenModel build() => LibraryScreenModel(
        viewType: {},
      );

  Future<void> fetchAllLibraries() async {
    Future<void> load() async {
      final cachedViews = ref.read(viewsProvider);
      final List<ViewModel> viewsList;
      if (cachedViews.views.isNotEmpty && !cachedViews.loading) {
        viewsList = cachedViews.views;
      } else {
        final views = await ref.read(viewsProvider.notifier).fetchViews();
        viewsList = views?.views.toList() ?? [];
      }
      state = state.copyWith(
        views: viewsList,
      );
      if (state.views.isEmpty) return;
      final viewModel = state.selectedViewModel ?? state.views.firstOrNull;
      if (viewModel == null) return;
      if (state.selectedViewModel?.id != viewModel.id) {
        await selectLibrary(viewModel);
      } else {
        state = state.copyWith(selectedViewModel: viewModel);
      }
      await loadLibrary(viewModel);
    }

    await SushiScreenTelemetry.trackLoad(screen: 'library', phase: 'fetch', load: load);
  }

  Future<void> selectLibrary(ViewModel viewModel) async {
    state = state.copyWith(
      selectedViewModel: viewModel,
      recommendations: const [],
      favourites: const [],
      genres: const [],
    );
  }

  Future<void> setViewType(Set<LibraryViewType> type) async {
    state = state.copyWith(viewType: type);
    final view = state.selectedViewModel;
    if (view != null) {
      await loadLibrary(view);
    }
  }

  Future<void> loadLibrary(ViewModel viewModel) async {
    final loadTypes = libraryLoadTypes(state);
    final loadRecommended = loadTypes.contains(LibraryViewType.recommended);
    final loadFavouritesSection = loadTypes.contains(LibraryViewType.favourites);
    final loadGenresSection = loadTypes.contains(LibraryViewType.genres);

    final results = await Future.wait<dynamic>([
      loadRecommended ? _fetchRecommendations(viewModel) : Future<dynamic>.value(null),
      loadFavouritesSection ? _fetchFavourites(viewModel) : Future<dynamic>.value(null),
      loadGenresSection ? _fetchGenres(viewModel) : Future<dynamic>.value(null),
    ]);

    state = state.copyWith(
      recommendations: loadRecommended ? (results[0] as List<RecommendedModel>?) ?? const [] : state.recommendations,
      favourites: loadFavouritesSection ? (results[1] as List<ItemBaseModel>?) ?? const [] : state.favourites,
      genres: loadGenresSection ? (results[2] as List<RecommendedModel>?) ?? const [] : state.genres,
    );
  }

  // Sushi has no HTTP backend (R-API-4) — recommendations/favourites/genres shelves here were
  // Jellyfin-only and never populate for a Sushi account.
  Future<List<RecommendedModel>> _fetchRecommendations(ViewModel viewModel) async => const [];

  Future<List<ItemBaseModel>> _fetchFavourites(ViewModel viewModel) async => const [];

  Future<List<RecommendedModel>> _fetchGenres(ViewModel viewModel) async => const [];

  void clear() {
    state = LibraryScreenModel(
      viewType: {},
    );
  }
}
