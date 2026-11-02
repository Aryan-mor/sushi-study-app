import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/sushi/sushi_search_navigation.dart';
import 'package:fladder/sushi/sushi_view_labels.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/metadata/refresh_metadata.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:fladder/widgets/navigation_scaffold/components/collapse_button.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_button.dart';
import 'package:fladder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:fladder/widgets/shared/custom_tooltip.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/simple_overflow_widget.dart';

final navBarNode = FocusNode();

/// Height of one rail item (NavigationButton, measured at 53dp) with a little slack.
const double _railItemExtent = 56;
const double _railDividerExtent = 16;

/// Where My videos (ADR 0037) goes among the home tabs: just above Synced, or last when there is no
/// Synced tab (web, downloads off).
int sushiMyVideosRailIndex(List<DestinationModel> destinations) {
  final synced = destinations.indexWhere((d) => d.route?.routeName == SyncedRoute.name);
  return synced < 0 ? destinations.length : synced;
}

class SideNavigationRail extends ConsumerStatefulWidget {
  final int currentIndex;
  final List<DestinationModel> destinations;
  final String currentLocation;
  final Widget child;
  final GlobalKey<ScaffoldState> scaffoldKey;
  const SideNavigationRail({
    required this.currentIndex,
    required this.destinations,
    required this.currentLocation,
    required this.child,
    required this.scaffoldKey,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SideNavigationRail();
}

class _SideNavigationRail extends ConsumerState<SideNavigationRail> {
  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;
    final views = ref.watch(viewsProvider.select((value) => value.views));
    final usePostersForLibrary = ref.watch(clientSettingsProvider.select((value) => value.usePosterForLibrary));
    final expandedSideBar = ref.watch(clientSettingsProvider.select((value) => value.expandSideBar));

    final expandedWidth = 200.0;

    final padding = MediaQuery.paddingOf(context);
    final directionalPadding = EdgeInsetsDirectional.fromSTEB(
      padding.left,
      padding.top + 8,
      padding.right,
      padding.bottom,
    );
    final startInset = directionalPadding.resolve(textDirection).left;
    final tooltipPosition = isRtl ? TooltipPosition.left : TooltipPosition.right;

    final largeBar = AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;
    final fullyExpanded = largeBar ? expandedSideBar : false;
    final shouldExpand = fullyExpanded;
    final isDesktop = AdaptiveLayout.of(context).isDesktop;

    final railPadding = directionalPadding
        .copyWith(
          start: startInset,
          end: 0,
          top: isDesktop ? directionalPadding.top : null,
        )
        .resolve(textDirection);
    final collapsedWidth = 90.0 + startInset;

    final fullScreenChildRoute = fullScreenRoutes.contains(context.router.current.name);

    final hasOverlay = AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual ||
        homeRoutes.any((element) => element.name.contains(context.router.current.name));

    final useBlurredBackground = ref.watch(clientSettingsProvider.select(
          (value) => value.backgroundImage == BackgroundType.blurred && value.enableBlurEffects,
        )) &&
        !topBarNoBlurRoutes.contains(context.router.current.name);

    final blurWidth = (shouldExpand ? expandedWidth : collapsedWidth) + 25;

    final surfaceColor = Theme.of(context).colorScheme.surface;

    final myVideosAt = sushiMyVideosRailIndex(widget.destinations);
    final myVideos = _myVideosButton(context, expandedSideBar, shouldExpand, tooltipPosition);
    Widget librariesOverflow(int remainingCount) => CustomTooltip(
          tooltipContent: expandedSideBar
              ? null
              : Container(
                  decoration: BoxDecoration(
                    borderRadius: FladderTheme.smallShape.borderRadius,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      context.localized.moreOptions,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
          position: tooltipPosition,
          child: PopupMenuButton(
            iconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            padding: EdgeInsets.zero,
            tooltip: "",
            icon: ExcludeFocus(
              child: NavigationButton(
                label: context.localized.other,
                selectedIcon: const Icon(IconsaxPlusLinear.arrow_square_down),
                icon: const Icon(IconsaxPlusLinear.arrow_square_down),
                expanded: shouldExpand,
                customIcon: usePostersForLibrary
                    ? ClipRRect(
                        borderRadius: FladderTheme.smallShape.borderRadius,
                        child: const SizedBox.square(
                          dimension: 50,
                          child: Card(
                            child: Icon(IconsaxPlusLinear.arrow_square_down),
                          ),
                        ),
                      )
                    : null,
                horizontal: true,
              ),
            ),
            itemBuilder: (context) => views
                .sublist(views.length - remainingCount)
                .map(
                  (e) => PopupMenuItem(
                    onTap: () => e.navigateToView(context),
                    child: Row(
                      spacing: 8,
                      children: [
                        usePostersForLibrary
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: ClipRRect(
                                  borderRadius: FladderTheme.smallShape.borderRadius,
                                  child: SizedBox.square(
                                    dimension: 45,
                                    child: FladderImage(
                                      image: e.imageData?.primary,
                                      placeHolder: Card(
                                        child: Icon(
                                          e.collectionType.iconOutlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Icon(e.collectionType.iconOutlined),
                        Text(e.name),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        );

    return Stack(
      children: [
        AdaptiveLayout(
          data: AdaptiveLayout.of(context).copyWith(
            // -0.1 offset to fix single visible pixel line
            sideBarWidth: (fullyExpanded ? expandedWidth : collapsedWidth) - 0.1,
          ),
          child: widget.child,
        ),
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: RepaintBoundary(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: !fullScreenChildRoute ? 1 : 0,
                child: IgnorePointer(
                  child: Container(
                    width: blurWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                        end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
                        colors: [
                          surfaceColor.withAlpha(255),
                          surfaceColor.withAlpha(175),
                          surfaceColor.withAlpha(0),
                        ],
                      ),
                    ),
                    child: useBlurredBackground
                        ? ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                                end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
                                colors: [
                                  Colors.white.withAlpha(255),
                                  Colors.white.withAlpha(175),
                                  Colors.white.withAlpha(0),
                                ],
                              ).createShader(
                                Rect.fromLTRB(0, 0, blurWidth, bounds.height),
                              );
                            },
                            blendMode: BlendMode.dstIn,
                            child: const BackgroundImage(),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: FocusTraversalGroup(
              policy: _RailTraversalPolicy(),
              child: IgnorePointer(
                ignoring: !hasOverlay || fullScreenChildRoute,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: !fullScreenChildRoute ? 1 : 0,
                  child: SizedBox(
                    width: shouldExpand ? expandedWidth : collapsedWidth,
                    child: Padding(
                      key: const Key('navigation_rail'),
                      padding: railPadding,
                      child: Column(
                        spacing: 2,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: CollapseButton(
                              label: shouldExpand ? Expanded(child: Text(context.localized.navigation)) : null,
                              keepVisible: !(largeBar && expandedSideBar),
                              icon: Icon(
                                largeBar && expandedSideBar ? IconsaxPlusLinear.sidebar_left : IconsaxPlusLinear.menu,
                                color: Theme.of(context).colorScheme.onSurface.withValues(
                                      alpha: largeBar && expandedSideBar ? 0.65 : 1,
                                    ),
                              ),
                              onPressed: !largeBar
                                  ? () => widget.scaffoldKey.currentState?.openDrawer()
                                  : () => ref
                                      .read(clientSettingsProvider.notifier)
                                      .update((state) => state.copyWith(expandSideBar: !state.expandSideBar)),
                            ),
                          ),
                          if (largeBar) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4).copyWith(bottom: expandedSideBar ? 10 : 0),
                              child: AnimatedFadeSize(
                                duration: const Duration(milliseconds: 250),
                                child: shouldExpand ? actionButton(context).extended : actionButton(context).normal,
                              ),
                            ),
                          ],
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
// A 1080p TV rail is 540dp tall. With every item in it there can be no room left for even the
// libraries' "Other" button, which then lands on Settings. Below that height the middle scrolls
// (focus scrolls it into view) and "Other" holds every library.
                                final items = widget.destinations.length + 1;
                                final tight = views.isNotEmpty &&
                                    largeBar &&
                                    constraints.maxHeight < (items + 1) * _railItemExtent + _railDividerExtent;
                                final column = Column(
                                  mainAxisSize: tight ? MainAxisSize.min : MainAxisSize.max,
                                  mainAxisAlignment: !largeBar ? MainAxisAlignment.center : MainAxisAlignment.start,
                                  children: [
                                    for (final (index, destination) in widget.destinations.indexed) ...[
                                      if (index == myVideosAt) myVideos,
                                      CustomTooltip(
                                        tooltipContent: expandedSideBar
                                            ? null
                                            : Card(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(12),
                                                  child: Text(
                                                    destination.label,
                                                    style: Theme.of(context).textTheme.titleSmall,
                                                  ),
                                                ),
                                              ),
                                        position: tooltipPosition,
                                        child: destination.toNavigationButton(
                                          widget.currentIndex == index,
                                          true,
                                          navFocusNode: index == 0,
                                          shouldExpand,
                                        ),
                                      ),
                                    ],
                                    if (myVideosAt == widget.destinations.length) myVideos,
                                    if (views.isNotEmpty && largeBar && !tight) ...[
                                      const Divider(
                                        indent: 32,
                                        endIndent: 32,
                                      ),
                                      Flexible(
                                        child: SimpleOverflowWidget(
                                          axis: Axis.vertical,
                                          children: views.map(
                                            (view) {
                                              final selected = context.router.currentUrl.contains(view.id);
                                              final actions = <ItemActionButton>[];
                                              return CustomTooltip(
                                                tooltipContent: expandedSideBar
                                                    ? null
                                                    : Container(
                                                        decoration: BoxDecoration(
                                                          borderRadius: FladderTheme.smallShape.borderRadius,
                                                          color: Theme.of(context).colorScheme.surface,
                                                        ),
                                                        child: Padding(
                                                          padding: const EdgeInsets.all(12),
                                                          child: Text(
                                                            sushiSyntheticViewLabel(context, view),
                                                            style: Theme.of(context).textTheme.titleSmall,
                                                          ),
                                                        ),
                                                      ),
                                                position: tooltipPosition,
                                                child: view.toNavigationButton(
                                                  selected,
                                                  true,
                                                  shouldExpand,
                                                  () => view.navigateToView(context),
                                                  label: sushiSyntheticViewLabel(context, view),
                                                  onSecondaryTapDown: actions.isEmpty
                                                      ? null
                                                      : (details) => _showContextMenu(
                                                            context,
                                                            ref,
                                                            details.globalPosition,
                                                            actions,
                                                          ),
                                                  onLongPress: actions.isEmpty
                                                      ? null
                                                      : () => showBottomSheetPill(
                                                            context: context,
                                                            content: (context, scrollController) => ListView(
                                                              shrinkWrap: true,
                                                              controller: scrollController,
                                                              children: actions.listTileItems(context, useIcons: true),
                                                            ),
                                                          ),
                                                  customIcon: usePostersForLibrary
                                                      ? Container(
                                                          decoration: BoxDecoration(
                                                            borderRadius: FladderTheme.smallShape.borderRadius,
                                                          ),
                                                          clipBehavior: Clip.hardEdge,
                                                          child: SizedBox.square(
                                                            dimension: 45,
                                                            child: FladderImage(
                                                              image: view.imageData?.primary,
                                                              placeHolder: Card(
                                                                child: Icon(
                                                                  selected
                                                                      ? view.collectionType.icon
                                                                      : view.collectionType.iconOutlined,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      : null,
                                                  trailing: actions,
                                                ),
                                              );
                                            },
                                          ).toList(),
                                          overflowBuilder: librariesOverflow,
                                        ),
                                      ),
                                    ],
                                    if (views.isNotEmpty && largeBar && tight) ...[
                                      const Divider(indent: 32, endIndent: 32),
                                      librariesOverflow(views.length),
                                    ],
                                  ],
                                );
                                return tight ? SingleChildScrollView(child: column) : column;
                              },
                            ),
                          ),
                          NavigationButton(
                            label: context.localized.settings,
                            selected: widget.currentLocation.contains(const SettingsRoute().routeName),
                            selectedIcon: const Icon(IconsaxPlusBold.setting_3),
                            horizontal: true,
                            expanded: shouldExpand,
                            icon: const SizedBox.shrink(),
                            customIcon: const ExcludeFocusTraversal(
                                child: SizedBox.square(dimension: 40, child: SettingsUserIcon())),
                            onPressed: () {
                              if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.single) {
                                context.router.push(const SettingsRoute());
                              } else {
                                context.router.push(const ClientSettingsRoute());
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // My videos (ADR 0037): one of the home tabs to look at, but not a destination -- that would also
  // put it in the phone's bottom bar.
  Widget _myVideosButton(BuildContext context, bool expandedSideBar, bool shouldExpand, TooltipPosition position) {
    return CustomTooltip(
      tooltipContent: expandedSideBar
          ? null
          : Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(context.localized.sushiMyVideos, style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
      position: position,
      child: NavigationButton(
        label: context.localized.sushiMyVideos,
        selected: widget.currentLocation.contains(const SushiMyVideosRoute().routeName),
        selectedIcon: const Icon(IconsaxPlusBold.video_play),
        icon: const Icon(IconsaxPlusLinear.video_play),
        horizontal: true,
        expanded: shouldExpand,
        onPressed: () => context.router.push(const SushiMyVideosRoute()),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref, Offset globalPos, List<ItemAction> actions) async {
    final position = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
    await showMenu(
      context: context,
      position: position,
      items: actions.popupMenuItems(useIcons: true),
    );
  }

  AdaptiveFab actionButton(BuildContext context) {
    return ((widget.currentIndex >= 0 && widget.currentIndex < widget.destinations.length)
            ? widget.destinations[widget.currentIndex].floatingActionButton
            : null) ??
        AdaptiveFab(
          context: context,
          title: context.localized.search,
          key: const Key("Search"),
          onPressed: () => sushiNavigateToSearch(context),
          child: const Icon(IconsaxPlusLinear.search_normal_1),
        );
  }
}

class _RailTraversalPolicy extends ReadingOrderTraversalPolicy {
  _RailTraversalPolicy();

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final toMainDirection = isRtl ? TraversalDirection.left : TraversalDirection.right;
    final awayFromMainDirection = isRtl ? TraversalDirection.right : TraversalDirection.left;

    if (direction == awayFromMainDirection) {
      return false;
    }
    if (direction == toMainDirection) {
      if (lastMainFocus != null && _isLaidOut(lastMainFocus!)) {
        lastMainFocus!.requestFocus();
        return true;
      } else {
        return super.inDirection(currentNode, direction);
      }
    }
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      final scope = currentNode.enclosingScope;
      if (scope == null) {
        return false;
      }

      final candidates = scope.traversalDescendants
          .where((n) => n.canRequestFocus && FocusTraversalGroup.maybeOfNode(n) == this && _isLaidOut(n))
          .toList();

      if (candidates.isEmpty) return false;

      final sorted = sortDescendants(candidates, currentNode).toList();

      var index = sorted.indexOf(currentNode);
      if (index == -1) {
        index = direction == TraversalDirection.down ? -1 : sorted.length;
      }

      final nextIndex = direction == TraversalDirection.down ? index + 1 : index - 1;

      if (nextIndex < 0 || nextIndex >= sorted.length) {
        return true;
      }

      requestFocusCallback(sorted[nextIndex]);
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

bool _isLaidOut(FocusNode node) {
  final ro = node.context?.findRenderObject();
  return ro is RenderBox && ro.hasSize;
}

bool isNodeInCurrentRoute(FocusNode node) {
  if (!node.canRequestFocus) return false;
  if (node.context == null) return false;

  final nearestScope = FocusScope.of(node.context!);
  return nearestScope.hasFocus || nearestScope.isFirstFocus;
}
