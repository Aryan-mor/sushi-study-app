import 'package:auto_route/auto_route.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/providers/search_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:fladder/widgets/shared/fladder_scrollbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

@RoutePage()
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Debouncer searchDebouncer = Debouncer(const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(searchProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    ref.read(searchProvider.notifier).setQuery(query);
    searchDebouncer.run(() {
      ref.read(searchProvider.notifier).searchQuery();
    });
    setState(() {});
  }

  void _onQuerySubmitted(String value) {
    ref.read(searchProvider.notifier).setQuery(value);
    ref.read(searchProvider.notifier).searchQuery();
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchProvider);
    final query = searchResults.searchQuery.trim();
    final showFirstLoad = searchResults.loading && !searchResults.hasAnyResults;
    final showEmpty = !searchResults.loading &&
        !searchResults.failed &&
        query.isNotEmpty &&
        !searchResults.hasAnyResults;

    final adaptiveLayout = AdaptiveLayout.of(context);
    final mediaQuery = MediaQuery.of(context);
    final floatingAppBar = AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;
    const toolbarHeight = 55.0;
    final sideBarPadding = EdgeInsetsDirectional.only(start: adaptiveLayout.sideBarWidth);
    final useBlurredBackground = ref.watch(clientSettingsProvider.select(
      (value) => value.backgroundImage == BackgroundType.blurred && value.enableBlurEffects,
    ));
    final useTVExpandedLayout = ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final rowPadding = AdaptiveLayout.adaptivePadding(context);
    // Movies first, then series, then anything else; "More from TMDB" is appended last.
    const typeOrder = [FladderItemType.movie, FladderItemType.series];
    int rank(FladderItemType type) {
      final i = typeOrder.indexOf(type);
      return i == -1 ? typeOrder.length : i;
    }

    final orderedResults = searchResults.results.entries.where((e) => e.value.isNotEmpty).toList()
      ..sort((a, b) => rank(a.key).compareTo(rank(b.key)));
    final posters = [
      ...searchResults.results.values.expand((e) => e),
      ...searchResults.missing,
    ];

    return MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(top: mediaQuery.padding.top + adaptiveLayout.topBarHeight),
        viewPadding: mediaQuery.viewPadding.copyWith(top: mediaQuery.viewPadding.top + adaptiveLayout.topBarHeight),
      ),
      child: NestedScaffold(
        background: BackgroundImage(images: posters.map((e) => e.images).nonNulls.toList()),
        body: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: FladderScrollbar(
            visible: AdaptiveLayout.inputDeviceOf(context) != InputDevice.pointer,
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverAppBar(
                  floating: !floatingAppBar,
                  collapsedHeight: 80,
                  toolbarHeight: 80,
                  automaticallyImplyLeading: false,
                  primary: true,
                  pinned: floatingAppBar,
                  elevation: 5,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  titleSpacing: 4,
                  flexibleSpace: RepaintBoundary(
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Theme.of(context).colorScheme.surface.withAlpha(255),
                            Theme.of(context).colorScheme.surface.withAlpha(0),
                          ],
                        ),
                      ),
                      child: useBlurredBackground
                          ? ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withAlpha(255),
                                    Colors.white.withAlpha(0),
                                  ],
                                ).createShader(
                                  Rect.fromLTRB(0, 10, bounds.width, bounds.height),
                                );
                              },
                              blendMode: BlendMode.dstIn,
                              child: const BackgroundImage(),
                            )
                          : null,
                    ),
                  ),
                  title: Padding(
                    padding: sideBarPadding,
                    child: Row(
                      spacing: 2,
                      children: [
                        const SizedBox(width: 2),
                        if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad)
                          Center(
                            child: SizedBox.square(
                              dimension: toolbarHeight,
                              child: Card(
                                elevation: 0,
                                child: context.router.backButton() ?? const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Flexible(
                          child: Hero(
                            tag: "PrimarySearch",
                            child: Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: FladderTheme.smallShape.borderRadius,
                              ),
                              shadowColor: Colors.transparent,
                              child: OutlinedTextField(
                                autoFocus: true,
                                controller: _controller,
                                textInputAction: TextInputAction.search,
                                onSubmitted: _onQuerySubmitted,
                                onChanged: _onQueryChanged,
                                searchQuery: (pattern) =>
                                    ref.read(searchProvider.notifier).fetchSuggestionNames(pattern),
                                placeHolder: "${context.localized.search}...",
                                decoration: InputDecoration(
                                  hintText: "${context.localized.search}...",
                                  prefixIcon: const Icon(IconsaxPlusLinear.search_normal),
                                  contentPadding: const EdgeInsets.only(top: 13),
                                  suffixIcon: _controller.text.isNotEmpty
                                      ? IconButton(
                                          onPressed: _clearQuery,
                                          icon: const Icon(Icons.clear),
                                        )
                                      : null,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(2),
                    child: AnimatedOpacity(
                      opacity: searchResults.loading ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const LinearProgressIndicator(minHeight: 2),
                    ),
                  ),
                ),
                if (showFirstLoad)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (searchResults.failed)
                  SliverFillRemaining(
                    child: Center(child: Text(context.localized.somethingWentWrong)),
                  )
                else if (showEmpty)
                  SliverFillRemaining(
                    child: Center(child: Text(context.localized.noResults)),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).height * 0.20),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        ...orderedResults.map(
                          (e) => PosterRow(
                            tvMode: useTVExpandedLayout,
                            contentPadding: rowPadding,
                            label: e.key.label(context.localized, count: 2),
                            posters: e.value,
                          ),
                        ),
                        if (searchResults.missing.isNotEmpty)
                          PosterRow(
                            tvMode: useTVExpandedLayout,
                            contentPadding: rowPadding,
                            label: context.localized.moreFromTmdb,
                            posters: searchResults.missing,
                            subTitleBuilder: (context, _) => Text(
                              context.localized.unavailable,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
