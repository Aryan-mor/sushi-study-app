import 'package:flutter/material.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/util/localization_helper.dart';

bool sushiDetailPosterBadgesEnabled(bool sushiDetailBadges) =>
    sushiDetailBadges;

Widget? sushiRelatedMediaTypeBadge(BuildContext context, ItemBaseModel poster) {
  final label = switch (poster) {
    MovieModel() => context.localized.mediaTypeMovie(1),
    SeriesModel() => context.localized.mediaTypeSeries(1),
    _ => switch (poster.jellyType) {
        BaseItemKind.movie => context.localized.mediaTypeMovie(1),
        BaseItemKind.series => context.localized.mediaTypeSeries(1),
        _ => null,
      },
  };
  if (label == null) return null;

  return Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: _typeChip(context, label),
    ),
  );
}

Widget _typeChip(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
    ),
  );
}
