import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/widgets/sushi_series_episode_picker_sheet.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

Future<void> sushiShowSeriesEpisodePicker({
  required BuildContext context,
  required WidgetRef ref,
  required SeriesModel series,
}) {
  return showBottomSheetPill(
    context: context,
    item: series,
    content: (context, scrollController) => SushiSeriesEpisodePickerSheet(series: series),
  );
}
