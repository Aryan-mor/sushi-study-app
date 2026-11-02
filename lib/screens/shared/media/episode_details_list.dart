import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/shared/media/episode_posters.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/humanize_duration.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/shared/focus_row.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

enum EpisodeDetailsViewType {
  list(icon: IconsaxPlusBold.grid_6),
  grid(icon: IconsaxPlusBold.grid_2);

  const EpisodeDetailsViewType({required this.icon});

  String label(BuildContext context) => switch (this) {
        EpisodeDetailsViewType.list => context.localized.list,
        EpisodeDetailsViewType.grid => context.localized.grid,
      };

  final IconData icon;
}

class EpisodeDetailsList extends ConsumerWidget {
  final EpisodeDetailsViewType viewType;
  final List<EpisodeModel> episodes;
  final EdgeInsets? padding;
  const EpisodeDetailsList({required this.viewType, required this.episodes, this.padding, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context).width /
        ((AdaptiveLayout.poster(context).gridRatio * 2) *
            ref.watch(clientSettingsProvider.select((value) => value.posterSize)));
    final decimals = size - size.toInt();
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
        );
    final columns = size.toInt().clamp(1, double.maxFinite).toInt();
    final spacing = (8 * decimals) + 8;
    // D-pad on TV, two separate traps this layout avoids:
    //  - FocusRow registers the episodes as a row group. Vertical d-pad from another row moves
    //    between registered groups (see adjacentRowGroup); without it UP from Cast jumped past the
    //    episodes to the top of the page.
    //  - Plain Column/Row instead of a shrink-wrapped GridView/ListView. Those are Scrollables even
    //    with NeverScrollableScrollPhysics, and Flutter's directional focus search only considers
    //    candidates in the focused node's own Scrollable while the page isn't scrolled to an edge —
    //    so DOWN from the header/description filtered out every episode and landed on Cast.
    return FocusRow(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (viewType) {
          EpisodeDetailsViewType.list => Padding(
              key: const ValueKey(EpisodeDetailsViewType.list),
              padding: padding ?? EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(episodes.length, (index) {
                  final episode = episodes[index];
                  List<Widget> children = [
                    Flexible(
                      flex: 1,
                      child: EpisodePoster(
                        episode: episode,
                        showLabel: false,
                        actions: episode.generateActions(context, ref),
                        onTap: () => episode.navigateTo(context),
                        onLongPress: () => _openEpisodeActions(context, ref, episode),
                        isCurrentEpisode: false,
                      ),
                    ),
                    const SizedBox(width: 16, height: 16),
                    Flexible(
                      flex: 3,
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SelectableText(
                                      episode.seasonEpisodeLabel(context.localized),
                                      style: textStyle,
                                    ),
                                    if (episode.overview.runTime != null)
                                      SelectableText(
                                        " - ${episode.overview.runTime!.humanize!}",
                                        style: textStyle,
                                      ),
                                  ],
                                ),
                                SelectableText(
                                  episode.name,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                SelectableText(
                                  episode.overview.summary,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ].addPadding(const EdgeInsets.symmetric(vertical: 4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ];
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: constraints.maxWidth > 800
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: children,
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: children,
                                  ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ),
          EpisodeDetailsViewType.grid => Padding(
              key: const ValueKey(EpisodeDetailsViewType.grid),
              padding: padding ?? EdgeInsets.zero,
              child: Column(
                spacing: spacing,
                children: [
                  for (var start = 0; start < episodes.length; start += columns)
                    Row(
                      spacing: spacing,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = start; index < start + columns; index++)
                          Expanded(
                            child: index < episodes.length
                                ? AspectRatio(
                                    aspectRatio: 1.67,
                                    child: EpisodePoster(
                                      episode: episodes[index],
                                      actions: episodes[index].generateActions(context, ref),
                                      onTap: () => episodes[index].navigateTo(context),
                                      onLongPress: () => _openEpisodeActions(context, ref, episodes[index]),
                                      isCurrentEpisode: false,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        },
      ),
    );
  }
}

void _openEpisodeActions(BuildContext context, WidgetRef ref, EpisodeModel episode) {
  showBottomSheetPill(
    context: context,
    item: episode,
    content: (context, scrollController) {
      return ListView(
        shrinkWrap: true,
        controller: scrollController,
        children: episode.generateActions(context, ref).listTileItems(context, useIcons: true).toList(),
      );
    },
  ).then((_) {
    if (context.mounted) context.refreshData();
  });
}
