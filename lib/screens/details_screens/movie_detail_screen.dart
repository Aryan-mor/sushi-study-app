import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/sushi/providers/sushi_catalog_item_flags.dart';
import 'package:fladder/sushi/sushi_library_detail_labels.dart';
import 'package:fladder/sushi/sushi_movie_watch_state.dart';
import 'package:fladder/sushi/sushi_detail_loading.dart';
import 'package:fladder/sushi/sushi_media_streams.dart';
import 'package:fladder/sushi/sushi_media_variant.dart';
import 'package:fladder/sushi/widgets/sushi_detail_action_layout.dart';
import 'package:fladder/sushi/sushi_detail_state.dart';
import 'package:fladder/sushi/sushi_home_pb.dart';
import 'package:fladder/sushi/sushi_item_adapter.dart';
import 'package:fladder/sushi/sushi_item_flags.dart';
import 'package:fladder/sushi/sushi_request_button.dart';
import 'package:fladder/sushi/sushi_row_adapter.dart';
import 'package:fladder/sushi/providers/sushi_trailer_provider.dart';
import 'package:fladder/sushi/widgets/sushi_trailer_action_button.dart';
import 'package:fladder/sushi/widgets/sushi_trailer_player.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/chapter_row.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/media/special_features_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/util/widget_extensions.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const MovieDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<MovieDetailScreen> {
  MovieDetailsProvider get providerInstance =>
      movieDetailsProvider(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final detailsRaw = ref.watch(providerInstance);
    final playedIds = ref.watch(sushiCatalogItemFlagsProvider.select((s) => s.playedIds));
    final details = detailsRaw == null
        ? null
        : sushiPaintMovieWatchState(detailsRaw, playedIds: playedIds);
    final wrapAlignment = AdaptiveLayout.viewSizeOf(context) != ViewSize.phone
        ? WrapAlignment.start
        : WrapAlignment.center;
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final hasPlayableMedia = details != null && sushiMovieHasPlayableMedia(details);
    // Only after /item has resolved (sushiTitleResolved): before that the placeholder card cannot
    // tell "no file" from "not loaded", which flashed Request before Play. Until resolved,
    // mainButton is null — neither Play nor Request.
    final sushiResolved = sushiTitleResolved(ref, details?.id, sushiEnabled: true);
    // Ready catalog files can still leave the picker empty (hard sub / dub hidden for a
    // non-Persian subtitle language). No Play means Request, even when a file exists.
    final sushiRequestTmdb = details != null && sushiResolved && !hasPlayableMedia
        ? sushiTmdbIdFromItemId(details.id)
        : null;
    final MediaStreamHelper? streamHelper = details != null &&
            sushiShowMediaStreamHelper(details.mediaStreams)
        ? MediaStreamHelper(
            mediaStream: details.mediaStreams,
            onItemChanged: (changed) {
              sushiOnUserMediaStreamsChanged(ref, changed, details);
              ref.read(providerInstance.notifier).setMediaStreamHelper(changed);
            },
          )
        : null;

    return DetailScaffold(
      label: widget.item.name,
      item: details,
      actions: (context) => details?.generateActions(
        context,
        ref,
        exclude: {
          ItemActions.play,
          ItemActions.playFromStart,
          ItemActions.details,
        },
        onDeleteSuccesFully: (item) {
          if (context.mounted) {
            context.router.popBack();
          }
        },
      ),
      onRefresh: () async =>
          await ref.read(providerInstance.notifier).fetchDetails(widget.item),
      backDrops: details?.images,
      content: (detailsContext, padding) {
        if (details == null) {
          return SushiDetailLoadingContent(item: widget.item, padding: padding);
        }
        final actionChildren = <Widget>[
            Consumer(
              builder: (context, ref, _) {
                final flags = ref.watch(sushiItemFlagsProvider)[details.id] ??
                    const SushiItemFlags();
                return SelectableIconButton(
                  onPressed: () async {
                    await ref
                        .read(sushiItemFlagsProvider.notifier)
                        .setWatchLater(details, !flags.watchLater);
                  },
                  selected: flags.watchLater,
                  selectedIcon: IconsaxPlusBold.clock,
                  icon: IconsaxPlusLinear.clock,
                );
              },
            ),
            if (details.userData.played)
              SelectableIconButton(
                onPressed: () async {
                  await ref.read(userProvider.notifier).markAsPlayed(false, details.id);
                },
                selected: true,
                selectedIcon: IconsaxPlusBold.tick_circle,
                icon: IconsaxPlusLinear.tick_circle,
              ),
            SelectableIconButton(
              refreshOnEnd: false,
              onPressed: () async {
                final trailer = await ref.read(
                  sushiTrailerStateProvider((itemId: details.id, kind: SushiKind.movie)).future,
                );
                if (!detailsContext.mounted) return;
                final actions = sushiInsertWatchedTrailer(
                  details.generateActions(detailsContext, ref, exclude: {
                    if (!hasPlayableMedia) ...{
                      ItemActions.play,
                      ItemActions.playFromStart,
                      ItemActions.download,
                    },
                  }),
                  state: trailer,
                  engaged: details.userData.played || details.progress != 0,
                  onOpen: () => SushiTrailerPlayer.open(
                    detailsContext,
                    youtubeKey: trailer.trailerKey,
                    title: details.name,
                  ),
                );
                await showBottomSheetPill(
                  context: detailsContext,
                  content: (context, scrollController) => ListView(
                    controller: scrollController,
                    shrinkWrap: true,
                    children: actions.listTileItems(context, useIcons: true),
                  ),
                );
              },
              selected: false,
              icon: IconsaxPlusLinear.more,
            ),
          ];
        final actionButtons = SushiDetailActionLayout(
          alignment: wrapAlignment,
          children: actionChildren,
        );
        final engaged = details.userData.played || details.progress != 0;
        final trailerState = ref
            .watch(sushiTrailerStateProvider((itemId: details.id, kind: SushiKind.movie)))
            .valueOrNull;
        final headerTrailer = !isPhone &&
                (trailerState?.hasTrailer ?? false) &&
                !(trailerState?.watched ?? false) &&
                !engaged
            ? SushiTrailerActionButton(
                itemId: details.id,
                kind: SushiKind.movie,
                title: details.name,
                compact: true,
              )
            : null;
        return Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OverviewHeader(
                    name: details.name,
                    image: details.images,
                    padding: padding,
                    mainButton: SushiDetailPrimaryRow(
                      itemId: details.id,
                      kind: SushiKind.movie,
                      title: details.name,
                      engaged: engaged,
                      inlineTrailer: isPhone,
                      versionHelper: streamHelper,
                      trailingActions: isPhone ? actionChildren : const [],
                      primary: hasPlayableMedia
                          ? MediaPlayButton(
                              item: details,
                              onLongPressed: (restart) async {
                                await details.play(
                                  detailsContext,
                                  ref,
                                  showPlaybackOption: true,
                                  startPosition: restart ? Duration.zero : null,
                                );
                              },
                              onPressed: (restart) async {
                                await details.play(
                                  detailsContext,
                                  ref,
                                  startPosition: restart ? Duration.zero : null,
                                );
                              },
                            )
                          : sushiRequestTmdb != null
                              ? SushiRequestButton(
                                  tmdbId: sushiRequestTmdb,
                                  kind: 1,
                                  prominent: true,
                                  onAlreadyAvailable: () => ref
                                      .read(providerInstance.notifier)
                                      .fetchDetails(widget.item),
                                )
                              : null,
                    ),
                    afterMediaStreams: headerTrailer,
                    centerButtons: isPhone ? null : actionButtons,
                    originalTitle: details.originalTitle,
                    productionYear: details.premiereDate.year.toString(),
                    runTime: details.overview.runTime,
                    genres: details.overview.genreItems,
                    studios: details.overview.studios,
                    officialRating: details.overview.parentalRating,
                    communityRating: details.overview.communityRating,
                    originCountry: sushiOriginCountry(details.id),
                    contentTags: details.overview.tags,
                    additionalLabels: sushiLibraryDetailLabels(
                      context,
                      ref,
                      widget.item.id,
                      details.overview,
                    ),
                    mediaStreamHelper: streamHelper,
                  ),
                  if (details.overview.summary.isNotEmpty == true)
                    ExpandingText(
                      text: details.overview.summary,
                    ).padding(padding),
                  if (details.chapters.isNotEmpty)
                    ChapterRow(
                      chapters: details.chapters,
                      contentPadding: padding,
                      onPressed: (chapter) {
                        details.play(
                          detailsContext,
                          ref,
                          startPosition: chapter.startPosition,
                        );
                      },
                    ),
                  if (details.overview.people.isNotEmpty)
                    PeopleRow(
                      people: details.overview.people,
                      contentPadding: padding,
                    ),
                  if (details.specialFeatures.isNotEmpty)
                    SpecialFeaturesRow(
                        contentPadding: padding,
                        label: detailsContext.localized
                            .specialFeature(details.specialFeatures.length),
                        specialFeatures: details.specialFeatures),
                  if (details.related.isNotEmpty)
                    PosterRow(
                      posters: details.related,
                      contentPadding: padding,
                      label: detailsContext.localized.related,
                      sushiDetailBadges: true,
                    ),
                  if (sushiCollectionFor(details.id)?.items.isNotEmpty ?? false)
                    PosterRow(
                      posters: sushiCollectionFor(details.id)!.items,
                      contentPadding: padding,
                      label: () {
                        final name = sushiCollectionFor(details.id)!.name;
                        return name.isEmpty ? 'Collection' : name;
                      }(),
                      sushiDetailBadges: false,
                    ),
                  if (details.overview.externalUrls?.isNotEmpty == true)
                    Padding(
                      padding: padding,
                      child: ExternalUrlsRow(
                        urls: details.overview.externalUrls,
                      ),
                    )
                ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
              ),
            );
      },
    );
  }
}
