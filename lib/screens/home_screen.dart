import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/sushi/sushi_search_navigation.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/input_handler.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/navigation_scaffold.dart';

enum HomeTabs {
  dashboard,
  favorites,
  watchLater,
  sync;

  const HomeTabs();

  IconData get icon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusLinear.home_1,
        HomeTabs.favorites => IconsaxPlusLinear.heart,
        HomeTabs.watchLater => IconsaxPlusLinear.clock,
        HomeTabs.sync => IconsaxPlusLinear.cloud,
      };

  IconData get selectedIcon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusBold.home_1,
        HomeTabs.favorites => IconsaxPlusBold.heart,
        HomeTabs.watchLater => IconsaxPlusBold.clock,
        HomeTabs.sync => IconsaxPlusBold.cloud,
      };

  Future navigate(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.router.navigate(const DashboardRoute()),
        HomeTabs.favorites => context.router.navigate(const FavouritesRoute()),
        HomeTabs.watchLater => context.router.navigate(const WatchLaterRoute()),
        HomeTabs.sync => context.router.navigate(const SyncedRoute()),
      };

  String label(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.localized.dashboard,
        HomeTabs.favorites => context.localized.favorites,
        HomeTabs.watchLater => context.localized.sushiWatchlist,
        HomeTabs.sync => context.localized.sync,
      };
}

@RoutePage()
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref.watch(showSyncButtonProviderProvider);
    final destinations = HomeTabs.values.map((e) {
      switch (e) {
        case HomeTabs.dashboard:
          return DestinationModel(
            label: context.localized.navigationDashboard,
            icon: const Icon(IconsaxPlusLinear.home_1),
            selectedIcon: const Icon(IconsaxPlusBold.home_1),
            route: const DashboardRoute(),
            action: () => e.navigate(context),
            floatingActionButton: AdaptiveFab(
              context: context,
              title: context.localized.search,
              key: Key(e.name.capitalize()),
              onPressed: () => sushiNavigateToSearch(context),
              child: const Icon(IconsaxPlusLinear.search_normal_1),
            ),
          );
        case HomeTabs.favorites:
          return DestinationModel(
            label: context.localized.navigationFavorites,
            icon: Icon(e.icon),
            selectedIcon: Icon(e.selectedIcon),
            route: const FavouritesRoute(),
            floatingActionButton: AdaptiveFab(
              context: context,
              title: context.localized.filter(0),
              key: Key(e.name.capitalize()),
              onPressed: () => context.router.navigate(LibrarySearchRoute(favourites: true)),
              child: const Icon(IconsaxPlusLinear.heart_search),
            ),
            action: () => e.navigate(context),
          );
        case HomeTabs.watchLater:
          return DestinationModel(
            label: context.localized.sushiWatchlist,
            icon: Icon(e.icon),
            selectedIcon: Icon(e.selectedIcon),
            route: const WatchLaterRoute(),
            action: () => e.navigate(context),
          );
        case HomeTabs.sync:
          if (canDownload && !kIsWeb) {
            return DestinationModel(
              label: context.localized.navigationSync,
              icon: Icon(e.icon),
              badge: Consumer(
                builder: (context, ref, child) {
                  final length = ref.watch(activeDownloadTasksProvider.select((value) => value.length));
                  return length != 0
                      ? CircleAvatar(
                          radius: 10,
                          child: FittedBox(
                            child: Text(length.toString()),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
              selectedIcon: Icon(e.selectedIcon),
              route: const SyncedRoute(),
              action: () => e.navigate(context),
            );
          }
          return null;
      }
    }).nonNulls.toList();

    return NotificationManagerInitializer(
      child: InputHandler<GlobalHotKeys>(
        autoFocus: false,
        keyMapResult: (result) {
          switch (result) {
            case GlobalHotKeys.toggleSideBar:
              ref.read(clientSettingsProvider.notifier).toggleSideBar();
              return true;
            case GlobalHotKeys.search:
              sushiNavigateToSearch(context);
              return true;
            case GlobalHotKeys.exit:
              Future.microtask(() async {
                final manager = WindowManager.instance;
                if (await manager.isClosable()) {
                  manager.close();
                } else {
                  FladderSnack.show(context.localized.somethingWentWrong, context: context);
                }
              });
              return true;
          }
        },
        keyMap: ref.watch(clientSettingsProvider.select((value) => value.currentShortcuts)),
        child: HeroControllerScope(
          controller: HeroController(),
          child: AutoRouter(
            builder: (context, child) {
              return CustomKeyboardWrapper(
                child: NavigationScaffold(
                  destinations: destinations,
                  currentRouteName: context.router.current.name,
                  nestedChild: child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
