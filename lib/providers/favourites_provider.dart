import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/favourites_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

final favouritesProvider = StateNotifierProvider<FavouritesNotifier, FavouritesModel>((ref) {
  return FavouritesNotifier(ref);
});

class FavouritesNotifier extends StateNotifier<FavouritesModel> {
  FavouritesNotifier(this.ref) : super(FavouritesModel());

  final Ref ref;

  Future<void> fetchFavourites() async {
    if (state.loading) return;

    state = state.copyWith(loading: true);

    final res = await sushiFetchList(scope: SushiListScope.favorites, sort: SushiListSort.name);
    final items = res?.rows.map(sushiRowToItemBaseModel).toList() ?? const <ItemBaseModel>[];
    state = state.copyWith(
      favourites: items.groupedItems,
      people: const [],
      loading: false,
    );
  }

  void setSearch(String value) {
    state = state.copyWith(searchQuery: value);
  }

  void clear() {
    state = FavouritesModel();
  }
}
