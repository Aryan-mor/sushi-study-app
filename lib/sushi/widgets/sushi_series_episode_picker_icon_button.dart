import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_episode_picker.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';

class SushiSeriesEpisodePickerIconButton extends ConsumerWidget {
  final SeriesModel series;

  const SushiSeriesEpisodePickerIconButton({
    required this.series,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = context.localized.episode(2);
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(16);

    return FocusButton(
      onTap: () => sushiShowSeriesEpisodePicker(
        context: context,
        ref: ref,
        series: series,
      ),
      borderRadius: borderRadius,
      darkOverlay: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: borderRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.video_vertical,
                size: 24,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
