import 'package:fladder/models/item_base_model.dart';

class SearchModel {
  final bool loading;
  final bool failed;
  final String searchQuery;
  final int resultCount;
  final Map<FladderItemType, List<ItemBaseModel>> results;
  final List<ItemBaseModel> missing;

  SearchModel({
    this.loading = false,
    this.failed = false,
    this.searchQuery = "",
    this.resultCount = 0,
    this.results = const {},
    this.missing = const [],
  });

  SearchModel copyWith({
    bool? loading,
    bool? failed,
    String? searchQuery,
    int? resultCount,
    Map<FladderItemType, List<ItemBaseModel>>? results,
    List<ItemBaseModel>? missing,
  }) {
    return SearchModel(
      loading: loading ?? this.loading,
      failed: failed ?? this.failed,
      searchQuery: searchQuery ?? this.searchQuery,
      resultCount: resultCount ?? this.resultCount,
      results: results ?? this.results,
      missing: missing ?? this.missing,
    );
  }

  bool get hasCatalogResults => results.values.any((list) => list.isNotEmpty);
  bool get hasAnyResults => hasCatalogResults || missing.isNotEmpty;
}
