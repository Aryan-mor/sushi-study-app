import 'package:fladder/models/search_model.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/sushi_search_transport.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchProvider = StateNotifierProvider<SearchNotifier, SearchModel>((ref) {
  return SearchNotifier(ref);
});

class SearchNotifier extends StateNotifier<SearchModel> {
  SearchNotifier(this.ref) : super(SearchModel());

  final Ref ref;

  Future<void> searchQuery() async {
    if (state.searchQuery.isEmpty) return;
    state = state.copyWith(loading: true, failed: false);
    final q = state.searchQuery;
    final res = await sushiFetchSearch(query: q);
    if (state.searchQuery != q) return;
    if (res == null) {
      state = state.copyWith(
        resultCount: 0,
        results: const {},
        missing: const [],
        loading: false,
        failed: true,
      );
      return;
    }
    final items = res.rows.map(sushiRowToItemBaseModel).toList();
    final missing = res.missing.map(sushiRowToItemBaseModel).toList();
    state = state.copyWith(
      resultCount: items.length + missing.length,
      results: items.groupedItems,
      missing: missing,
      loading: false,
      failed: false,
    );
  }

  void setQuery(String searchQuery) {
    state = state.copyWith(searchQuery: searchQuery);
  }

  /// Names for Fladder TV slide-in keyboard suggestions. Catalog + missing, cap [limit].
  Future<List<String>> fetchSuggestionNames(String query, {int limit = 3}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final res = await sushiFetchSearch(query: trimmed);
    if (res == null) return [];
    return [
      ...res.rows.map(sushiRowToItemBaseModel),
      ...res.missing.map(sushiRowToItemBaseModel),
    ].map((e) => e.name).where((name) => name.isNotEmpty).take(limit).toList();
  }

  void clear() {
    state = SearchModel();
  }
}
