import 'package:flutter/material.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/sushi/sushi_series_episode_actions.dart';
import 'package:fladder/sushi/widgets/sushi_series_episode_picker_icon_button.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

class SushiSeriesDetailPlayButtons extends StatelessWidget {
  final SeriesModel series;
  final EpisodeModel episode;
  final Future<void> Function(bool restart) onPlay;
  final Future<void> Function(bool restart)? onLongPlay;

  const SushiSeriesDetailPlayButtons({
    required this.series,
    required this.episode,
    required this.onPlay,
    this.onLongPlay,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final pickerSeasons = sushiSeriesPickerSeasons(series);
    final episodeCount = pickerSeasons.fold<int>(0, (sum, season) => sum + (season.episodeCount > 0 ? season.episodeCount : season.episodes.length));
    final showEpisodePicker = episodeCount > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final expand = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone &&
            constraints.hasBoundedWidth &&
            constraints.maxWidth < double.infinity;
        return Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(
              fit: expand ? FlexFit.tight : FlexFit.loose,
              child: MediaPlayButton(
                item: episode,
                onPressed: onPlay,
                onLongPressed: onLongPlay,
              ),
            ),
            if (showEpisodePicker) ...[
              const SizedBox(width: 4),
              SushiSeriesEpisodePickerIconButton(series: series),
            ],
          ],
        );
      },
    );
  }
}
