import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/library_search_provider.dart';
import 'package:fladder/screens/shared/chips/category_chip.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/shared/button_group.dart';

class LibraryFilterChips extends ConsumerStatefulWidget {
  const LibraryFilterChips({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _LibraryFilterChipsState();
}

class _LibraryFilterChipsState extends ConsumerState<LibraryFilterChips> {
  @override
  Widget build(BuildContext context) {
    final uniqueKey = widget.key ?? UniqueKey();
    final libraryProvider = ref.watch(librarySearchProvider(uniqueKey).notifier);
    final favourites = ref.watch(librarySearchProvider(uniqueKey).select((v) => v.filters.favourites));
    final librarySearchResults = ref.watch(librarySearchProvider(uniqueKey));

    final chips = [
      ExpressiveButton(
        isSelected: favourites == true,
        icon: favourites == true ? const Icon(IconsaxPlusBold.heart) : null,
        label: Text(context.localized.favorites),
        onPressed: () {
          libraryProvider.toggleFavourite();
          context.refreshData();
        },
      ),
      if (librarySearchResults.filters.genres.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.genre(librarySearchResults.filters.genres.length)),
          activeIcon: IconsaxPlusBold.hierarchy_2,
          items: librarySearchResults.filters.genres,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setGenres(value),
          onCancel: () => libraryProvider.setGenres(librarySearchResults.filters.genres),
          onClear: () => libraryProvider.setGenres(librarySearchResults.filters.genres.setAll(false)),
        ),
      if (librarySearchResults.filters.years.isNotEmpty)
        CategoryChip<int>(
          label: Text(context.localized.year(librarySearchResults.filters.years.length)),
          items: librarySearchResults.filters.years,
          labelBuilder: (item) => Text(item.toString()),
          onSave: (value) => libraryProvider.setYears(value),
          onCancel: () => libraryProvider.setYears(librarySearchResults.filters.years),
          onClear: () => libraryProvider.setYears(librarySearchResults.filters.years.setAll(false)),
        ),
    ];

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Row(
        spacing: 4,
        children: chips.mapIndexed(
          (index, element) {
            final position = index == 0
                ? PositionContext.first
                : (index == chips.length - 1 ? PositionContext.last : PositionContext.middle);
            return PositionProvider(position: position, child: element);
          },
        ).toList(),
      ),
    );
  }
}
