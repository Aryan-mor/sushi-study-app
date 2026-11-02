import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/sushi/sushi_home_unique.dart';
import 'package:fladder/sushi/sushi_list_pb.dart';
import 'package:fladder/sushi/sushi_list_transport.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';

export 'package:fladder/sushi/sushi_home_unique.dart' show sushiHomeForYouLimit;

class SushiForYouDashboardData {
  const SushiForYouDashboardData({this.items = const []});

  final List<ItemBaseModel> items;

  static const empty = SushiForYouDashboardData();
}

/// For You rail (LIST_SCOPE_FOR_YOU): follow/fav unfinished, plus non-followed series played
/// in the last 14 days with an unfinished episode (follow ranks higher).
final sushiForYouDashboardProvider = FutureProvider<SushiForYouDashboardData>((ref) async {
  final res = await sushiFetchList(scope: SushiListScope.forYou);
  final items = res?.rows.take(sushiHomeForYouLimit).map(sushiRowToItemBaseModel).toList() ??
      const <ItemBaseModel>[];
  if (items.isEmpty) return SushiForYouDashboardData.empty;
  return SushiForYouDashboardData(items: items);
});
